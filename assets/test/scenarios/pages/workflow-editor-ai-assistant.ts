// The workflow editor's AI assistant panel
// (annotations/views/workflow-editor-ai-assistant.md): the header's AI button,
// the panel with its menu, conversation list, messages and message box, and a
// stand-in for the Apollo service Lightning asks for every reply. Everything
// here knows how today's panel is built: its test ids, the icon-only AI
// button, the channel topic and its events, the stream Apollo answers with.
// Specs find things through these helpers, so a rebuild only changes this
// file. Editor-wide helpers are in ./workflow-editor.
import { createServer } from 'node:http';

import { expect, type Locator, type Page } from '@playwright/test';
import YAML from 'yaml';

import { exec, lastLine, onNode, open, sql, user } from '../steps';

import {
  breadcrumbs,
  header,
  headerTooltip,
  openEditor,
} from './workflow-editor';

// A reply goes through a background job and a stream, so it gets this long
const REPLY = { timeout: 20000 };

// ---------------------------------------------------------------------------
// Whether the instance has the assistant, and turning it off
// ---------------------------------------------------------------------------

export const NEEDS_KEY =
  'needs AI_ASSISTANT_API_KEY set when the e2e Lightning starts';

type Instance = { enabled: boolean; endpoint: string | null };
let instance: Instance | undefined;

// Whether Lightning was started with the assistant configured, and the
// Apollo endpoint it calls. Asked once per worker.
export function assistantOnInstance(): Instance {
  instance ??= JSON.parse(
    JSON.parse(
      lastLine(
        onNode(
          'Jason.encode!(%{enabled: Lightning.AiAssistant.enabled?(), endpoint: Lightning.Config.apollo(:endpoint)})'
        )
      )
    ) as string
  ) as Instance;
  return instance;
}

// Given the instance has no AI key, as on an instance without the assistant.
// Instance-wide: a test that uses it is @serial. Returns a function that puts
// the key back.
export function withoutAssistant() {
  const was = lastLine(
    onNode('Lightning.Config.apollo(:ai_assistant_api_key)')
  ).trim();
  const put = (key: string) =>
    onNode(
      `Application.put_env(:lightning, :apollo, Keyword.put(Application.get_env(:lightning, :apollo, []), :ai_assistant_api_key, ${key}))`
    );
  put('nil');
  return () => void put(was);
}

// ---------------------------------------------------------------------------
// The Apollo stand-in. Lightning posts each message to
// <endpoint>/services/global_chat/stream (job_chat and workflow_chat only
// for old conversations) and reads the reply as server-sent events: Anthropic
// text deltas and thinking blocks, a "changes" event carrying the workflow
// YAML ahead of the text, an "error" event, and a final "complete" event with
// the whole reply. Only one process can listen on the port, so every test
// that starts it is @serial.
// ---------------------------------------------------------------------------

export type ApolloRequest = {
  path: string;
  content: string;
  workflow_yaml?: string;
  page?: string;
  history?: { role: string; content: string }[];
  attachments?: { type: string; content: unknown }[];
};

// One part of a reply: an event sent, a wait until a promise settles, or the
// connection dropped there
export type ReplyStep =
  | { event: string; data: unknown }
  | { wait: Promise<unknown> }
  | 'cut';

// A reply, or one made from the request it answers
export type Reply = ReplyStep[] | ((request: ApolloRequest) => ReplyStep[]);

export type StandInApollo = Awaited<ReturnType<typeof standInApollo>>;

// Starts the stand-in on the port of the endpoint Lightning was started with.
// Each request takes the next queued reply, or the standing one.
export async function standInApollo() {
  const endpoint = assistantOnInstance().endpoint ?? 'http://localhost:3000';
  const port = Number(new URL(endpoint).port || 80);
  const requests: ApolloRequest[] = [];
  const queue: Reply[] = [];
  let standing: Reply = answer('Here is what I found.');

  const server = createServer((req, res) => {
    void (async () => {
      if (req.method !== 'POST') return void res.writeHead(200).end();
      const chunks: Buffer[] = [];
      for await (const chunk of req) chunks.push(chunk as Buffer);
      const body = JSON.parse(
        Buffer.concat(chunks).toString('utf8') || '{}'
      ) as Omit<ApolloRequest, 'path'>;
      const request = { ...body, path: req.url ?? '' };
      requests.push(request);
      const reply = queue.shift() ?? standing;
      const steps = typeof reply === 'function' ? reply(request) : reply;
      res.writeHead(200, {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
      });
      // Headers and each event go out before the next step, so a cut comes
      // after what was sent, not before it
      res.flushHeaders();
      for (const step of steps) {
        if (step === 'cut') return void res.socket?.end();
        if ('wait' in step) await step.wait;
        else
          await new Promise(resolve =>
            res.write(
              `event: ${step.event}\ndata: ${JSON.stringify(step.data)}\n\n`,
              resolve
            )
          );
      }
      res.end();
    })();
  });
  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, () => resolve());
  });

  return {
    // What the panel's messages asked, oldest first
    asked: () => requests.filter(r => r.path.includes('/stream')),
    // The next requests get these replies, in order
    replyWith(...replies: Reply[]) {
      queue.push(...replies);
    },
    // Every request after the queued ones gets <reply>
    always(reply: Reply) {
      standing = reply;
    },
    async stop() {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    },
  };
}

const delta = (text: string) => ({
  event: 'content_block_delta',
  data: { type: 'content_block_delta', delta: { type: 'text_delta', text } },
});

// The assistant starts thinking (the panel shows "Thinking...")
export const thinking: ReplyStep = {
  event: 'content_block_start',
  data: { type: 'content_block_start', content_block: { type: 'thinking' } },
};

// A piece of the reply's text, as it streams
export const chunk = (text: string): ReplyStep => delta(text);

// The end of a reply that says <text>, carrying workflow <yaml> if given; a
// code edit that could not be applied is reported the way Apollo's planner
// reports it (a job agent call that applied no patches)
export const done = (
  text: string,
  {
    yaml,
    codeEditFailed = false,
  }: { yaml?: string; codeEditFailed?: boolean } = {}
): ReplyStep => ({
  event: 'complete',
  data: {
    response: text,
    attachments: yaml ? [{ type: 'workflow_yaml', content: yaml }] : [],
    usage: {},
    meta: codeEditFailed
      ? { subagent_calls: [{ diff: { patches_applied: 0 } }] }
      : {},
  },
});

// A whole reply saying <text>; a workflow is sent ahead of the text, as
// Apollo does, and again with the end
export const answer = (
  text: string,
  opts: { yaml?: string; codeEditFailed?: boolean } = {}
): ReplyStep[] => [
  ...(opts.yaml ? [{ event: 'changes', data: { yaml: opts.yaml } }] : []),
  chunk(text),
  done(text, opts),
];

// A step that holds the reply until open() is called
export function gate() {
  let open!: () => void;
  const wait = new Promise<void>(resolve => (open = resolve));
  return { step: { wait } as ReplyStep, open };
}

// The workflow files the panel sends and applies: today's v1 format, jobs and
// edges keyed by hyphenated names
type WorkflowFile = {
  name: string;
  jobs: Record<string, { name: string; body?: string; adaptor?: string }>;
  edges: Record<string, Record<string, unknown>>;
  [key: string]: unknown;
};

const keyOf = (name: string) => name.toLowerCase().replace(/\s+/g, '-');

// The workflow the panel sent with <request>, changed by <changes>, as the
// YAML the assistant answers with
export function edited(
  request: ApolloRequest,
  ...changes: ((wf: WorkflowFile) => void)[]
) {
  const wf = YAML.parse(request.workflow_yaml ?? '') as WorkflowFile;
  for (const change of changes) change(wf);
  return YAML.stringify(wf);
}

// ...with step <name> added after step <after>
export const addStep =
  (name: string, after: string, body = 'fn(state => state);') =>
  (wf: WorkflowFile) => {
    const from = Object.keys(wf.jobs).find(k => wf.jobs[k].name === after)!;
    wf.jobs[keyOf(name)] = {
      name,
      adaptor: '@openfn/language-common@latest',
      body,
    };
    wf.edges[`${from}->${keyOf(name)}`] = {
      source_job: from,
      target_job: keyOf(name),
      condition_type: 'on_job_success',
      enabled: true,
    };
  };

// ...with step <name>'s code replaced by <body>
export const setBody = (name: string, body: string) => (wf: WorkflowFile) => {
  const key = Object.keys(wf.jobs).find(k => wf.jobs[k].name === name)!;
  wf.jobs[key].body = body;
};

// ...with step <name> missing its code, which the panel will not apply
export const dropBody = (name: string) => (wf: WorkflowFile) => {
  const key = Object.keys(wf.jobs).find(k => wf.jobs[k].name === name)!;
  delete wf.jobs[key].body;
};

// A new workflow <name>: a webhook trigger leading to step <step>
export const newWorkflowFile = (
  name: string,
  step = 'Fetch patients',
  { withBody = true } = {}
) =>
  YAML.stringify({
    name,
    jobs: {
      [keyOf(step)]: {
        name: step,
        adaptor: '@openfn/language-common@latest',
        ...(withBody && { body: 'fn(state => state);' }),
      },
    },
    triggers: { webhook: { type: 'webhook', enabled: false } },
    edges: {
      [`webhook->${keyOf(step)}`]: {
        source_trigger: 'webhook',
        target_job: keyOf(step),
        condition_type: 'always',
        enabled: true,
      },
    },
  });

// ---------------------------------------------------------------------------
// The header's AI button. Today an icon-only button whose name is only in
// its tooltip, so it is found by its icon inside the header.
// ---------------------------------------------------------------------------

export const aiButton = (page: Page) =>
  header(page)
    .getByRole('button', { name: /AI Assistant/ })
    .or(header(page).locator('button:has(> .hero-chat-bubble-left-right)'))
    .first();

// What the AI button's tooltip says. Today a Radix tooltip; on a disabled
// button the pointer may never reach it. Right after a click or a menu, a
// pointer that comes straight back opens nothing, so it rests away first.
export async function aiButtonTip(page: Page) {
  await page.mouse.move(0, 0);
  await page.waitForTimeout(400);
  return headerTooltip(page, aiButton(page));
}

// ---------------------------------------------------------------------------
// The panel
// ---------------------------------------------------------------------------

// The assistant panel; absent while it is closed
export const panel = (page: Page) =>
  page.getByRole('complementary', { name: 'AI Assistant' });

// When I open workflow <workflowId> with the panel open (and <query>, such as
// a conversation or a run), signed in already
export async function openWithPanel(
  page: Page,
  projectId: string,
  workflowId: string,
  query: Record<string, string> = {}
) {
  const params = new URLSearchParams({ chat: 'true', ...query });
  await openEditor(page, projectId, workflowId, `?${params.toString()}`);
  await expect(panel(page)).toBeVisible();
}

// Which conversation the URL names ("new", an id, or none)
export const chatInUrl = (page: Page) =>
  new URL(page.url()).searchParams.get('w-chat');

export const messageBox = (page: Page) =>
  panel(page)
    .getByRole('textbox', { name: /^Ask me anything/ })
    .or(panel(page).getByPlaceholder(/^Ask me anything/))
    .first();

export const sendButton = (page: Page) =>
  panel(page).getByRole('button', { name: /^(Send message|Sending\.\.\.)$/ });

// When I type <text> in the message box and press Enter, once it takes input
export async function ask(page: Page, text: string) {
  await expect(messageBox(page)).toBeEnabled(REPLY);
  await messageBox(page).fill(text);
  await messageBox(page).press('Enter');
}

// What the message box's tooltip says while it is disabled. Today the
// tooltip hangs off the box's wrapper.
export const messageBoxTip = (page: Page) =>
  headerTooltip(page, messageBox(page).locator('xpath=..'));

// The messages I and others sent, and the assistant's settled replies
export const sentMessages = (page: Page) =>
  panel(page).getByTestId('user-message');
export const replies = (page: Page) =>
  panel(page).getByTestId('assistant-message');

// Waits until the conversation shows <n> settled replies and the box takes
// input again
export async function repliesSettled(page: Page, n: number) {
  await expect(replies(page)).toHaveCount(n, REPLY);
  await expect(messageBox(page)).toBeEnabled(REPLY);
}

// The steps a reply lists as changed. Today a diff block per step, titled
// with what happened to it and its name.
export const changedStep = (within: Locator, name: string) =>
  within.getByTestId('diff-block').filter({ hasText: name });

// The reply's link that opens a changed step in the code editor
export const openStepButton = (within: Locator, name: string) =>
  changedStep(within, name).getByRole('button', { name: 'Open', exact: true });

export const revertButton = (page: Page) =>
  panel(page).getByRole('button', { name: 'Revert changes', exact: true });
export const restoreButton = (page: Page) =>
  panel(page).getByRole('button', { name: 'Restore changes', exact: true });

// The panel's "More options" menu
export async function openPanelMenu(page: Page) {
  await panel(page).getByRole('button', { name: 'More options' }).click();
}

// When I choose <item> from the panel's menu
export async function choosePanelMenu(
  page: Page,
  item: 'Conversations' | 'About the AI Assistant'
) {
  await openPanelMenu(page);
  await panel(page).getByRole('button', { name: item }).click();
}

export const aboutDialog = (page: Page) =>
  panel(page).getByRole('dialog', { name: 'About the AI Assistant' });

// The conversation list: one button per conversation, its title first
const conversationItems = (page: Page) =>
  panel(page).getByTestId('session-list-item');

export const conversationItem = (page: Page, title: string) =>
  conversationItems(page).filter({
    has: page.getByRole('heading', { name: title, exact: true }),
  });

// The titles listed, top to bottom
export const listedConversations = (page: Page) =>
  conversationItems(page).locator('h4').allInnerTexts();

export const loadMoreButton = (page: Page) =>
  panel(page).getByRole('button', { name: /^Load \d+ more$/ });

export async function searchConversations(page: Page, term: string) {
  await panel(page)
    .getByRole('textbox', { name: 'Search conversations...' })
    .or(panel(page).getByPlaceholder('Search conversations...'))
    .first()
    .fill(term);
}

// ---------------------------------------------------------------------------
// Around the panel
// ---------------------------------------------------------------------------

// When I switch the open workflow to version <v> from the version chip
export async function switchToVersion(page: Page, v: number) {
  await breadcrumbs(page)
    .getByRole('button', { name: /^(latest|v\S+|unpublished|•)$/i })
    .click();
  await page
    .getByRole('menu')
    .getByRole('menuitem', { name: new RegExp(`^\\s*v${v}(\\s|$)`) })
    .click();
}

// When I start a new workflow in project <projectId> with "Build with AI"
// and <prompt>, signed in already
export async function buildWithAi(
  page: Page,
  projectId: string,
  prompt: string
) {
  await open(page, `/projects/${projectId}/w/new`);
  await page.getByRole('textbox', { name: 'Build with AI' }).fill(prompt);
  await page.getByRole('button', { name: /Build it/ }).click();
  await expect(panel(page)).toBeVisible();
}

// ---------------------------------------------------------------------------
// The assistant's channel, joined from a second connection signed in as the
// same person as <page>: a stand-in for the panel's own channel where the
// editor page itself would be torn down (removed from the project) or would
// not send the frame (a viewer's context update, another project's run).
// ---------------------------------------------------------------------------

type ChannelReply = { status: string; response: Record<string, unknown> };

export type AiChannel = Awaited<ReturnType<typeof aiChannelAs>>;

// Joins conversation <sessionId> ("new" starts one, with <params>) — resolves
// once the server has answered the join
export async function aiChannelAs(
  page: Page,
  sessionId: string,
  params: Record<string, unknown> = {}
) {
  const token = await page.evaluate(
    () => (window as unknown as { userToken?: string }).userToken ?? ''
  );
  const url = new URL('/socket/websocket', page.url());
  url.protocol = url.protocol.replace('http', 'ws');
  url.search = new URLSearchParams({ token, vsn: '2.0.0' }).toString();
  const topic = `ai_assistant:workflow_template:${sessionId}`;
  const ws = new WebSocket(url);
  const answers = new Map<string, ChannelReply>();
  let closed = false;
  let refs = 0;

  ws.onmessage = e => {
    const [, ref, from, event, payload] = JSON.parse(String(e.data)) as [
      string,
      string | null,
      string,
      string,
      ChannelReply,
    ];
    if (from !== topic) return;
    if (event === 'phx_reply' && ref) answers.set(ref, payload);
    if (event === 'phx_close' || event === 'phx_error') closed = true;
  };
  await new Promise((resolve, reject) => {
    ws.onopen = resolve;
    ws.onerror = reject;
  });
  const beat = setInterval(
    () => ws.send(JSON.stringify([null, 'hb', 'phoenix', 'heartbeat', {}])),
    20000
  );
  ws.onclose = () => clearInterval(beat);

  const send = async (event: string, payload: Record<string, unknown>) => {
    const ref = String(++refs);
    ws.send(JSON.stringify(['1', ref, topic, event, payload]));
    await expect
      .poll(() => answers.has(ref), `server answered ${event}`)
      .toBe(true);
    return answers.get(ref)!;
  };
  const joined = await send('phx_join', params);

  return {
    joined,
    // Whether the server has closed the channel
    closed: () => closed,
    // When I send <event> on the channel — resolves to the server's answer
    push: send,
    close() {
      clearInterval(beat);
      ws.close();
    },
  };
}

// The reason a refused join or frame gives
export const reasonOf = (reply: ChannelReply) =>
  (reply.response as { reason?: string }).reason;

// The parameters the panel joins with to start a conversation on workflow
// <workflowId> with <content>
export const newConversationParams = (
  projectId: string,
  workflowId: string,
  content: string,
  extra: Record<string, unknown> = {}
) => ({
  project_id: projectId,
  workflow_id: workflowId,
  content,
  use_global_assistant: true,
  ...extra,
});

// When <page>'s person lists the project's conversations over HTTP, as the
// conversation list may — resolves to the response status
export async function listConversationsOverHttp(
  page: Page,
  projectId: string,
  workflowId: string
) {
  const res = await page.request.get(
    `/api/ai_assistant/sessions?session_type=workflow_template&project_id=${projectId}&workflow_id=${workflowId}`
  );
  return res.status();
}

// ---------------------------------------------------------------------------
// Seeding and reading conversations
// ---------------------------------------------------------------------------

export type MessageSeed = {
  role: 'user' | 'assistant';
  content: string;
  /** who sent it (user messages) */
  by?: string;
  status?: 'success' | 'error' | 'processing' | 'pending';
  failure?: string;
};

export type ConversationSeed = {
  title: string;
  workflowId: string;
  by: string;
  messages?: MessageSeed[];
  /** last updated this many minutes ago */
  minutesAgo?: number;
};

// Given these conversations exist in project <projectId>, saved straight to
// the database so no reply is asked for. A "processing" message started a
// day ago. Resolves to their ids, in order.
export function seedConversations(
  projectId: string,
  seeds: ConversationSeed[]
): string[] {
  const data = seeds.map(s => ({
    title: s.title,
    project_id: projectId,
    workflow_id: s.workflowId,
    user_id: user(s.by).id,
    minutes_ago: s.minutesAgo ?? 0,
    messages: (
      s.messages ?? [
        { role: 'user', content: s.title, by: s.by },
        { role: 'assistant', content: 'Here is what I found.' },
      ]
    ).map(m => ({
      role: m.role,
      content: m.content,
      status: m.status ?? 'success',
      user_id: m.role === 'user' ? user(m.by ?? s.by).id : null,
      failure: m.failure ?? null,
    })),
  }));
  const out = onNode(`
    alias Lightning.AiAssistant.{ChatMessage, ChatSession}
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    ids = for s <- Jason.decode!(${JSON.stringify(JSON.stringify(data))}) do
      at = DateTime.add(now, -s["minutes_ago"] * 60, :second)
      session = Lightning.Repo.insert!(%ChatSession{session_type: "workflow_template", title: s["title"],
        project_id: s["project_id"], workflow_id: s["workflow_id"], user_id: s["user_id"],
        meta: %{"message_options" => %{"use_global_assistant" => true}}, inserted_at: at, updated_at: at})
      count = length(s["messages"])
      s["messages"] |> Enum.with_index() |> Enum.each(fn {m, i} ->
        Lightning.Repo.insert!(%ChatMessage{chat_session_id: session.id, role: String.to_existing_atom(m["role"]),
          content: m["content"], status: String.to_existing_atom(m["status"]), user_id: m["user_id"],
          failure_message: m["failure"], meta: (if m["role"] == "assistant", do: %{"from_global" => true}, else: %{}),
          processing_started_at: (if m["status"] == "processing", do: DateTime.add(DateTime.utc_now(), -86400, :second)),
          inserted_at: DateTime.add(at, i - count, :second), updated_at: at})
      end)
      session.id
    end
    Jason.encode!(ids)`);
  return JSON.parse(JSON.parse(lastLine(out)) as string) as string[];
}

// Removes every conversation in project <projectId>
export const removeConversationsOf = (projectId: string) =>
  exec(`delete from ai_chat_sessions where project_id = '${projectId}'`);

export type StoredConversation = {
  id: string;
  title: string;
  workflow_id: string | null;
  follow_run_id: string | null;
};

// The conversations of project <projectId>, newest first
export const conversationsOf = (projectId: string) =>
  sql<StoredConversation>(
    `select id, title, workflow_id, meta->>'follow_run_id' as follow_run_id
     from ai_chat_sessions where project_id = '${projectId}' order by inserted_at desc`
  );

export type StoredMessage = {
  id: string;
  role: string;
  content: string;
  status: string;
  apply_failed: boolean;
};

// The messages of conversation <sessionId>, oldest first
export const messagesOf = (sessionId: string) =>
  sql<StoredMessage>(
    `select id, role::text as role, content, status::text as status,
            coalesce((meta->>'apply_failed')::boolean, false) as apply_failed
     from ai_chat_messages where chat_session_id = '${sessionId}' order by inserted_at, id`
  );

// Given the stored workflow on conversation <sessionId>'s replies is
// replaced by <yaml> (a stand-in for a retry that succeeds)
export const replaceReplyWorkflow = (sessionId: string, yaml: string) =>
  exec(`update ai_chat_messages set code = $y$${yaml}$y$
        where chat_session_id = '${sessionId}' and role = 'assistant' and code is not null`);

// When the stuck-message sweep runs now, as its cron would
export const runStuckMessageSweep = () =>
  onNode(
    'Lightning.AiAssistant.StuckMessageReaper.perform(%Oban.Job{args: %{}})'
  );

// Job <jobId>'s project credential as saved
export const credentialOfJob = (jobId: string) =>
  sql<{ id: string | null }>(
    `select project_credential_id as id from jobs where id = '${jobId}'`
  )[0]?.id;

// Given project <projectId> requires MFA
export const requireMfa = (projectId: string) =>
  exec(`update projects set requires_mfa = true where id = '${projectId}'`);
