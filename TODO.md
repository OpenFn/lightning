# TODO


### User story

### Details

Ensure everything in the below list has been implemented: 
- [ ] Able to create new jobs
   - [x] #825
   - [ ] saving 
   - [x] #884
   - [ ] #885
   - [ ] #886
   - [ ] delete a job #830
- [ ] #877
- [ ] #878
- [ ] #887
- [ ] Delete/replace WorkflowLive #874

Replace workflow-live with the new-workflow builder. 

### Implementation notes

### Release notes

### User acceptance criteria / tests to check 

**Workflow Index**

- index lists all workflows for a project
- Projects viewers can't edit or delete a workflow

**Workflow Edit**

- Can create a new job
- Can edit an existing job
- For new jobs, the default for adaptor name and version defaults to common and latest
- Metadata section of job editor should display "no credential" when a credential is missing
- **Should be able to delete a job** <-- @amberrignell to think about this https://github.com/OpenFn/Lightning/issues/830
- Tootips should display the correct text for adaptor, credential and trigger
  _Should test the tooltips when doing the first test that uses the form_

- Trigger form should have dropdown for cron or webhook 

- Clicking new credential, should open the credential modal, should create a new credential, should update the job's credential

- cron_setup_component can create a new job with a default cron trigger
- cron_setup_component can set trigger to daily, weekly, monthly cron 

**Running a Job**

- Users can run any job with a custom input
- Users can select from inputs of the 3 latest runs (when jobs have existing runs)
- Users can see the output when they manually run a job 

_Still to be sorted_

- POST /users/register creates account and logs the user in
- POST /users/register creates account and initial project and logs the user in

- **trigger node should display the trigger type (instead of new trigger)** 

- project viewers cannot create new workflows
- project viewers cannot edit workflows
- new job can be created without an upstream job, with an upstream job
- **should be able to delete workflow**
- edit workflow renders to workflow canvas

New: 
- When you click on "edit" on a job, should see the job name, adaptor (just the type, not the full language-package) and credential. 
- When there is no credential, should see "No credential" (not "No credentials")
- should be able to sace from the job inspector

Noticed bugs: 
- you have to click twice to select a credential
- 

Questions/discussion: 
- if you remove a job, what happens to the edges? 
- if you remove a job and add another job 



- - -

How to get to it
http://localhost:4000/projects/2ebf0e27-7748-4724-b310-4f5128149de9/w-new

- - -

- [x] Mount component
- [x] Attach store
- [x] Add node
- [x] pass node back to liveview
- [ ] remove node

- [x] Generate JSON patch from immer store
- [x] Send JSON patch to liveview

- [ ] ensure that changes don't override each other
- [ ] can save a workflow

> https://medium.com/@mweststrate/distributing-state-changes-using-snapshots-patches-and-actions-part-2-2f50d8363988

---

- Need to set the current node in the store

Store should be initialised outside of the component? Store -> add nodes on
start

Changeset -> Liveview -> Hook -> Store -> Component or Changeset -> Liveview ->
Hook -> Component -> Store

Do we need something in between the hook and the store? Liveview is going to
send the changeset to the hook, which will then send it to the component.
However we need a way for the stores changes to be sent back to liveview

```js
{
  nodes: [
    { id: 1, type: "trigger" },
    { id: 2, name: "test2", },
    { id: 3, name: "test3", }
  ],
  edges: [
    { id: 1, source: 1, condition: "true", target: 2, },
    { id: 2, source: 2, condition: ":on_success", target: 3, }
  ]
}
```

```elixir
Workflow.changeset(%Workflow{}, %{
  "jobs" => [
    %{"id" => 2, "name" => "job-1"},
    %{"id" => 3, "name" => "job-3"}
  ],
  "triggers" => [
    %{"id" => 1, "type" => "webhook"}
  ],
  "edges" => [
    %{"id" => 1, "source_trigger_id" => 1, "condition" => "true", "target_job_id" => 2},
    %{"id" => 2, "source_job_id" => 2, "condition" => ":on_success", "target_job_id" => 3}
  ]
})
```

---

syncing the store with the changeset

1. Only send changes to LiveView on _user_ actions
2. Uniquely stamp messages with a UUID

3. Add a Job to the store, and call LiveView, and with the callback add or
   remove the Job from the store..

No. 3 requires the server to be able to manipulate the params as messages come
in. This runs the risk of the server and client getting out of sync.

`params` will need to be a struct that is set up early, and can be updated and
merged with form params.

changeset is what we want in the end forms will submit params react store will
send params

---

What about?

- concurrency limits
- When the CLI isn't available, like wrong path?
- What kind of errors does cli metadata return.
- file missing, not returned from cli or decode error.
- debug logging for the cli

- - -


*Vanilla is better*

"Reference live view implementation" leaning on the "layers" that I want Peter to do.

Bad live view:

standardized 
- authorization failure

I need to take some time to decide what I want with all of the issues Taylor and I have
and what Peter has proposed and come up with some agreed spec/design.

Make stories for:

edge form
trigger form
job builder 2.0