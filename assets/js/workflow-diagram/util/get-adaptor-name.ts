export default specifier => {
  if (specifier) {
    const [prefix, name] = specifier.match(/@openfn.language-(.+)@/);
    return name || 'unknown';
  }
  return '';
};
