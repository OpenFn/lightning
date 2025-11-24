export const getVisibilityProps = () => {
  if (typeof document.hidden !== 'undefined') {
    return { hidden: 'hidden', visibilityChange: 'visibilitychange' };
  }

  if (
    // @ts-expect-error webkitHidden not defined
    typeof (document as unknown as Document).webkitHidden !== 'undefined'
  ) {
    return {
      hidden: 'webkitHidden',
      visibilityChange: 'webkitvisibilitychange',
    };
  }
  // @ts-expect-error mozHidden not defined
  if (typeof (document as unknown as Document).mozHidden !== 'undefined') {
    return { hidden: 'mozHidden', visibilityChange: 'mozvisibilitychange' };
  }
  // @ts-expect-error msHidden not defined
  if (typeof (document as unknown as Document).msHidden !== 'undefined') {
    return { hidden: 'msHidden', visibilityChange: 'msvisibilitychange' };
  }
  return null;
};
