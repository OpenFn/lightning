// Writes the JSON Schema of each design-system page's `Props`, the type of
// the `data-props` its LiveView sends, for the ExUnit page tests to check
// the props against (LightningWeb.DesignSystemHelpers.page_props/2). The
// shell's is named after its hook, SidebarBridge. Run with
// `npm run ds:schemas`; CI fails when the checked-in ones are stale.
import { mkdirSync, writeFileSync } from 'node:fs';
import { basename } from 'node:path';

import {
  createFormatter,
  createParser,
  createProgram,
  DEFAULT_CONFIG,
  SchemaGenerator,
} from 'ts-json-schema-generator';

const OUT = '../test/support/design_system_schemas';

const config = {
  ...DEFAULT_CONFIG,
  path: 'js/design-system/{pages/*,shell}.tsx',
  tsconfig: 'tsconfig.design-system.json',
  jsDoc: 'none',
  strictTuples: true,
  topRef: false,
  // npm run ds:check type-checks these files with the .d.ts this glob leaves out.
  skipTypeCheck: true,
};
const program = createProgram(config);
const generator = new SchemaGenerator(
  program,
  createParser(program, config),
  createFormatter(config),
  config
);

mkdirSync(OUT, { recursive: true });
for (const file of program.getRootFileNames()) {
  const props = program
    .getSourceFile(file)
    .statements.find(statement => statement.name?.text === 'Props');
  if (!props) throw new Error(`${file} exports no Props type`);

  let schema = generator.createSchemaFromNodes([props]);
  // An alias (`type Props = SomePageProps`) comes out as a root $ref, and
  // ex_json_schema ignores the definitions beside one, so inline it.
  if (schema.$ref) {
    const { $ref, definitions, ...rest } = schema;
    const { [decodeURIComponent($ref.split('/').pop())]: root, ...others } =
      definitions;
    schema = { ...rest, ...root, definitions: others };
  }

  const name = basename(file, '.tsx');
  writeFileSync(
    `${OUT}/${name === 'shell' ? 'SidebarBridge' : name}.json`,
    `${JSON.stringify(schema, null, 2)}\n`
  );
}
