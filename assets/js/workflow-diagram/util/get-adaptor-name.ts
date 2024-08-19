export default (specifier: string) => {
  if (specifier && specifier.startsWith('@openfn/language')) {
    const result = specifier.match(/@openfn\/language-(.+)@/);
    if (result) {
      const [_prefix, name] = result;
      return name || 'unknown';
    }
  }
  return specifier ?? '';
};
