import { fetchDTSListing, fetchFile } from '@openfn/describe-package';

import dts_es5 from '../../editor/lib/es5.min.dts';

export type Lib = {
  content: string;
  filePath?: string;
};

/**
 * Load TypeScript definition files for an adaptor from jsDelivr
 *
 * Fetches .d.ts files for the specified adaptor and @openfn/language-common,
 * then wraps them in appropriate module declarations for Monaco editor.
 *
 * @param specifier - Fully qualified adaptor name (e.g., "@openfn/language-http@5.0.0")
 * @returns Array of lib objects containing TypeScript definitions
 *
 * @example
 * const libs = await loadDTS('@openfn/language-http@5.0.0');
 * monaco.languages.typescript.javascriptDefaults.setExtraLibs(libs);
 */
export async function loadDTS(specifier: string): Promise<Lib[]> {
  // Work out the module name from the specifier
  // (this gets a bit tricky with @openfn/ module names)
  const nameParts = specifier.split('@');
  nameParts.pop(); // remove the version
  const name = nameParts.join('@');

  const results: Lib[] = [{ content: dts_es5 }];

  // Load common into its own module
  // TODO maybe we need other dependencies too? collections?
  if (name !== '@openfn/language-common') {
    const pkg = await fetchFile(`${specifier}/package.json`);
    const commonVersion = (JSON.parse(pkg || '{}') as any).dependencies?.[
      '@openfn/language-common'
    ];

    // jsDeliver doesn't appear to support semver range syntax (^1.0.0, 1.x, ~1.1.0)
    const commonVersionMatch = commonVersion?.match(/^\d+\.\d+\.\d+/);
    if (!commonVersionMatch) {
      console.warn(
        `@openfn/language-common@${commonVersion} contains semver range syntax.`
      );
    }

    const commonSpecifier = `@openfn/language-common@${commonVersion.replace(
      '^',
      ''
    )}`;
    for await (const filePath of fetchDTSListing(commonSpecifier)) {
      if (!filePath.startsWith('node_modules')) {
        // Load every common typedef into the common module
        let content = await fetchFile(`${commonSpecifier}${filePath}`);
        content = content.replace(/\* +@(.+?)\*\//gs, '*/');
        results.push({
          content: `declare module '@openfn/language-common' { ${content} }`,
        });
      }
    }
  }

  // This will store types.d.ts, if we can find it
  let types = '';

  // This stores string content for our adaptor
  let adaptorDefs: string[] = [];

  for await (const filePath of fetchDTSListing(specifier)) {
    if (!filePath.startsWith('node_modules')) {
      let content = await fetchFile(`${specifier}${filePath}`);
      // Convert relative paths
      content = content
        .replace(/from '\.\//g, `from '${name}/`)
        .replace(/import '\.\//g, `import '${name}/`);

      // Remove js doc annotations
      // this regex means: find a * then an @ (with 1+ space in between), then match everything up to a closing comment */
      // content = content.replace(/\* +@(.+?)\*\//gs, '*/');

      const fileName = filePath.split('/').at(-1)!.replace('.d.ts', '');

      // Import the index as the global namespace - but take care to convert all paths to absolute
      if (fileName === 'index' || fileName === 'Adaptor') {
        // It turns out that "export * as " seems to straight up not work in Monaco
        // So this little hack will refactor import statements in a way that works
        content = content.replace(
          /export \* as (\w+) from '(.+)';/g,
          `

          import * as $1 from '$2';
          export { $1 };`
        );
        adaptorDefs.push(`declare namespace {
  {{$TYPES}}
  ${content}
`);
      } else if (fileName === 'types') {
        types = content;
      } else {
        // Declare every other module as file
        adaptorDefs.push(`declare module '${name}/${fileName}' {
  {{$TYPES}}
  ${content}
}`);
      }
    }
  }

  // This just ensures that the global type defs appear in every scope
  // This is basically a hack to work around https://github.com/OpenFn/lightning/issues/2641
  // If we find a types.d.ts, append it to every other file
  adaptorDefs = adaptorDefs.map(def => def.replace('{{$TYPES}}', types));

  results.push(
    ...adaptorDefs.map(content => ({
      content,
    }))
  );

  return results;
}
