export default specifier => {
  if (specifier && specifier.startsWith('@openfn.language')) {
    const [prefix, name] = specifier.match(/@openfn.language-(.+)@/);
    return name || 'unknown';
  }
  return specifier ?? '';
};
