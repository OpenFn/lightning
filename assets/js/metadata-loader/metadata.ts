// TODO shoud models be pre sorted?
// Maybe! But I don't know if I want to rely on that?
const sortArr = (arr: any[]) => {
  arr.sort((a, b) => {
    const astr = typeof a === 'string' ? a : a.name;
    const bstr = typeof b === 'string' ? b : b.name;

    if (astr === bstr) return 0;
    if (astr > bstr) {
      return 1;
    } else {
      return -1;
    }
  });
  return arr;
};

const sortDeep = (model: any) => {
  if (model.children) {
    if (Array.isArray(model.children)) {
      model.children = sortArr(model.children.map(sortDeep));
    } else {
      const keys = Object.keys(model.children).sort();
      model.children = keys.reduce((acc, key) => {
        acc[key] = sortArr(model.children[key].map(sortDeep));
        return acc;
      }, {});
    }
  }
  return model;
};

export { sortDeep as sortMetadata };
