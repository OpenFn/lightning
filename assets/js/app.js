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
import JobEditor from './job-editor';
import WorkflowDiagram from './workflow-diagram';
import TabSelector from './tab-selector';

let dragEndListener;
let dragListener;

let Hooks = {
  WorkflowDiagram,
  TabSelector,
  JobEditor,
};

Hooks.Flash = {
  mounted() {
    let hide = () =>
      liveSocket.execJS(this.el, this.el.getAttribute('phx-click'));
    this.timer = setTimeout(() => hide(), 5000);
    this.el.addEventListener('phx:hide-start', () => clearTimeout(this.timer));
    this.el.addEventListener('mouseover', () => {
      clearTimeout(this.timer);
      this.timer = setTimeout(() => hide(), 5000);
    });
  },
  destroyed() {
    clearTimeout(this.timer);
  },
};
Hooks.AssocListChange = {
  mounted() {
    this.el.addEventListener('change', _event => {
      this.pushEventTo(this.el, 'select_item', { id: this.el.value });
    });
  },
};

Hooks.AutoResize = {
  mounted() {
    this.parent = this.el.parentElement;
    this.el.style.height = `${this.parent.clientHeight - 1}px`;

    this.listener = addEventListener('resize', _event => {
      this.el.style.height = `${this.parent.clientHeight - 1}px`;
    });
  },
  destroyed() {
    removeEventListener('resize', this.listener);
  },
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
  disconnectWorkflowResizer();
});

window.addEventListener('phx:page-loading-stop', () => {
  clearTimeout(topBarScheduled);
  topBarScheduled = undefined;
  topbar.hide();
  connectWorkflowResizer();
});

// The drag mask stops the cursor interacting with the page while dragging
const addDragMask = () => {
  const dragMask = document.createElement('div');
  dragMask.id = 'drag-mask';
  dragMask.style.position = 'absolute';
  dragMask.style.left = 0;
  dragMask.style.right = 0;
  dragMask.style.top = 0;
  dragMask.style.bottom = 0;
  dragMask.style.userSelect = 'none';
  dragMask.style.zIndex = 999;
  dragMask.style.cursor = 'ew-resize';
  document.body.appendChild(dragMask);
};

const disconnectWorkflowResizer = () => {
  const el = document.getElementById('resizer');
  if (el) {
    // el.removeEventListener('dragend', dragEndListener);
    // el.removeEventListener('drag', dragListener);
  }
};

const connectWorkflowResizer = () => {
  const el = document.getElementById('resizer');
  if (el) {
    const savedWidth = localStorage.getItem('lightning.job-editor.width');
    if (savedWidth) {
      el.parentNode.style.width = `${savedWidth}%`;
    }

    // find the parent h-full element, which we'll size against
    let parent = el.parentNode;
    while (parent && !parent.className.match('h-full')) {
      parent = parent.parentNode;
    }
    if (parent) {
      const parentBounds = parent.getBoundingClientRect();
      const parentWidth = parentBounds.width;
      const parentLeft = parentBounds.left;
      let width;

      el.addEventListener('pointerdown', () => {
        addDragMask();
        dragListener = e => {
          if (e.screenX !== 0) {
            // Work out the mouse position relative to the parent
            const relativePosition = Math.max(
              0,
              Math.min((e.clientX - parentLeft) / parentWidth)
            );
            // Invert the postion
            width = (1 - relativePosition) * 100;
            // Update the width
            el.parentNode.style.width = `${width}%`;
          }
        };
        document.addEventListener('mousemove', dragListener);
      });

      document.addEventListener('pointerup', () => {
        if (dragListener) {
          const mask = document.getElementById('drag-mask');
          mask.parentNode.removeChild(mask);
          localStorage.setItem('lightning.job-editor.width', width);
          document.dispatchEvent(new Event('update-layout'));
          document.removeEventListener('mousemove', dragListener);
          dragListener = null;
        }
      });
    }
  }
};

// connect if there are any LiveViews on the page
liveSocket.connect();
// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;
