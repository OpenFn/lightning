import { PhoenixHook } from './PhoenixHook';

const LogLineHighlight = {
  mounted() {
    console.log(this.el.dataset);

    this.highlightRows();
  },
  updated() {
    console.log({updated: this.el.dataset['selectedRunId']});
    
    this.highlightRows();
  },
  highlightRows() {
    const selectedRunId = this.el.dataset['selectedRunId'];
    this.el.querySelectorAll('[data-run-id]').forEach(el => {
      let runId = (el as HTMLElement).dataset['runId'];

      if (runId === selectedRunId) {
        el.classList.add('bg-slate-600');
      } else {
        el.classList.remove('bg-slate-600');
      }
    });
  },
} as PhoenixHook<{
  highlightRows: () => void;
}>;

export default LogLineHighlight;
