const is = (x: unknown, y: unknown) =>
  // @ts-ignore
  (x === y && (x !== 0 || 1 / x === 1 / y)) || (x !== x && y !== y);

const objectIs = typeof Object.is === 'function' ? Object.is : is;

const hasOwnProperty = Object.prototype.hasOwnProperty;

// React's default compare algo for `React.memo`
// assets/node_modules/react-dom/cjs/react-dom.development.js
export const shallowEqual = (objA: unknown, objB: unknown) => {
  if (objectIs(objA, objB)) {
    return true;
  }

  if (
    typeof objA !== 'object' ||
    objA === null ||
    typeof objB !== 'object' ||
    objB === null
  ) {
    return false;
  }

  const keysA = Object.keys(objA);
  const keysB = Object.keys(objB);

  if (keysA.length !== keysB.length) {
    return false;
  } // Test for A's keys different from B.

  for (let i = 0; i < keysA.length; i++) {
    const currentKey = keysA[i];

    if (
      !hasOwnProperty.call(objB, currentKey) ||
      // @ts-ignore
      !objectIs(objA[currentKey], objB[currentKey])
    ) {
      return false;
    }
  }

  return true;
};
