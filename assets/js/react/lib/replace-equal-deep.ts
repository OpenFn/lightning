/* https://github.com/TanStack/query/pull/6481 */

/**
 * This function returns `a` if `b` is deeply equal.
 * If not, it will replace any deeply equal children of `b` with those of `a`.
 * This can be used for structural sharing between JSON values for example.
 */
export function replaceEqualDeep<T>(a: unknown, b: T): T;
export function replaceEqualDeep(a: unknown, b: unknown): unknown {
  if (a === b) {
    return a;
  }

  if (a instanceof Date && b instanceof Date) {
    return a.getTime() === b.getTime() ? a : b;
  }

  const array = isPlainArray(a) && isPlainArray(b);

  if (array || (isPlainObject(a) && isPlainObject(b))) {
    const aSize = array ? a.length : Object.keys(a).length;
    const bItems = array ? b : Object.keys(b);
    const bSize = bItems.length;
    const copy = array ? [] : {};

    let equalItems = 0;

    for (let i = 0; i < bSize; i++) {
      const key = String(array ? i : bItems[i]);
      copy[key] = replaceEqualDeep(a[key] as unknown, b[key] as unknown);
      if (copy[key] === a[key]) {
        equalItems++;
      }
    }

    return aSize === bSize && equalItems === aSize ? a : copy;
  }

  return b;
}

function isPlainArray(value: unknown): value is unknown[] {
  return Array.isArray(value) && value.length === Object.keys(value).length;
}

// Copied from: https://github.com/jonschlinkert/is-plain-object
// eslint-disable-next-line @typescript-eslint/no-wrapper-object-types
function isPlainObject(o: unknown): o is Object {
  if (!hasObjectPrototype(o)) {
    return false;
  }

  // If has no constructor
  const ctor = 'constructor' in o ? o.constructor : undefined;
  if (typeof ctor === 'undefined') {
    return true;
  }

  // If has modified prototype
  const prot =
    'prototype' in ctor.prototype ? (ctor.prototype as unknown) : undefined;
  if (!hasObjectPrototype(prot)) {
    return false;
  }

  // If constructor does not have an Object-specific method
  if (!Object.prototype.hasOwnProperty.call(prot, 'isPrototypeOf')) {
    return false;
  }

  // Most likely a plain Object
  return true;
}

// eslint-disable-next-line @typescript-eslint/no-wrapper-object-types
function hasObjectPrototype(o: unknown): o is Object {
  return Object.prototype.toString.call(o) === '[object Object]';
}
