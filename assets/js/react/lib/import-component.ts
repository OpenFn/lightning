import * as ReactIs from 'react-is';
import invariant from 'tiny-invariant';

/**
 * Load the source file and resolve with a reference to the React component.
 *
 * The file should export a React component as a named export matching the
 * provided name or as the default export.
 */
export const importComponent = async <const Props = object>(
  url: string,
  name = 'default'
): Promise<React.ComponentType<Props>> => {
  const exports = (await import(url)) as unknown;

  const Component =
    typeof exports === 'object' &&
    exports !== null &&
    name in exports &&
    exports[name] != null
      ? (exports[name] as unknown)
      : null;

  invariant(
    ReactIs.isValidElementType(Component) && typeof Component !== 'string',
    `No suitable export found in file \`${url}\`! Please export a React component as ${name === 'default' ? 'the default export' : `a named export with name \`${name}\``}!`
  );

  return Component;
};
