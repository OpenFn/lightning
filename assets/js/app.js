// We import the CSS which is extracted to its own file by esbuild.
// Remove this line if you add a your own CSS build pipeline (e.g postcss).

// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import 'phoenix_html';
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from 'phoenix';
import { LiveSocket } from 'phoenix_live_view';

import topbar from '../vendor/topbar';
import { AssocListChange, Copy, Flash, DownloadProject } from './hooks';
import JobEditor from './job-editor';
import JobEditorResizer from './job-editor-resizer/mount';
import TabSelector from './tab-selector';
import WorkflowDiagram from './workflow-diagram-old';
import WorkflowEditor from './workflow-editor';

let Hooks = {
  WorkflowDiagram,
  TabSelector,
  JobEditor,
  JobEditorResizer,
  WorkflowEditor,
  Flash,
  AssocListChange,
  Copy,
  DownloadProject,
};

// @ts-ignore
let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute('content');

let liveSocket = new LiveSocket('/live', Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
  dom: {
    onBeforeElUpdated(from, to) {
      // If an element has any of the 'lv-keep-*' attributes, copy across
      // the given attribute to maintain various styles and properties
      // that have had their control handed-over to a Hook or JS implementation.
      if (from.attributes['lv-keep-style']) {
        to.setAttribute('style', from.attributes.style.value);
      }

      if (from.attributes['lv-keep-class']) {
        to.setAttribute('class', from.attributes.class.value);
      }
    },
  },
});

// Show progress bar on live navigation and form submits
// Include a 120ms timeout to avoid small flashes when things load quickly.
topbar.config({ barColors: { 0: '#29d' }, shadowColor: 'rgba(0, 0, 0, .3)' });

let topBarScheduled = undefined;

window.addEventListener('phx:page-loading-start', () => {
  if (!topBarScheduled) {
    topBarScheduled = setTimeout(() => topbar.show(), 120);
  }
});

window.addEventListener('phx:page-loading-stop', () => {
  clearTimeout(topBarScheduled);
  topBarScheduled = undefined;
  topbar.hide();
});

window.addEventListener('phx:download_project', e => {
  const { file, link } = e.detail;
  const downloadLink = document.createElement('a');
  downloadLink.href = link;
  downloadLink.download = file;
  downloadLink.style.display = 'none';
  document.body.appendChild(downloadLink);
  downloadLink.click();
  document.body.removeChild(downloadLink);
});

window.addEventListener('keydown', event => {
  const currentURL = window.location.pathname;
  const edit_job_url = /\/projects\/(.+)\/w\/(.+)\/j\/(.+)/;
  if ((event.ctrlKey || event.metaKey) && event.key === 's') {
    if (edit_job_url.test(currentURL)) {
      event.preventDefault();
      console.log('Saving the job');
      let form = document.querySelector("button[form='job-form']");
      form.click();
    }
  }
});

// connect if there are any LiveViews on the page
liveSocket.connect();
// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;
