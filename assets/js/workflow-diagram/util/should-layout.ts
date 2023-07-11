// This function will determine whether we should run a layout on a model
// This generates a simple hash from the edges and compares it to the last hash
import { Flow } from '../types';

export default (edges: Flow.Edge[], lastHash?: string) => {
  const id = edges
    .map(e => `${e.source}-${e.target}`)
    .sort()
    .join('--');

  if (id !== lastHash) {
    return id;
  }
};
