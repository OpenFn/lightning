import invariant from 'tiny-invariant';

import * as ReactIs from 'react-is';

/**
 * Load the source file and resolve with a reference to the React component.
 *
 * The file should export a React component as a named export matching the
 * provided name or as the default export.
 */
export const importComponent = async <const Props = {}>(
  url: string,
  name = 'default'
): Promise<React.ComponentType<Props>> => {
  const exports = await import(url);

  const Component =
    name in exports && exports[name] != null ? exports[name] : null;

  invariant(
    ReactIs.isValidElementType(Component) && typeof Component !== 'string',
    `No suitable export found in file \`${url}\`! Please export a React component as ${name === 'default' ? 'the default export' : `a named export with name \`${name}\``}!`
  );

  return Component;
};
