// DataclipViewer.ts
import { PhoenixHook } from '../hooks/PhoenixHook';
import { mount } from './component';

type DataclipViewer = PhoenixHook<{}>;

export default {
  mounted(this: DataclipViewer) {
    this.fetchDataclipContent()
      .then(content => {
        mount(this.el, content);
      })
      .catch(error => {
        console.error('Failed to fetch content:', error);
      });
  },
  async fetchDataclipContent(): Promise<string> {
    const url = `/dataclip/body/${this.el.dataset.id}`;
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error('Network response was not ok');
    }
    return response.text();
  },
} as DataclipViewer;
