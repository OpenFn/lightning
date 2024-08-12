import React from 'react';
import { createRoot } from 'react-dom/client';
import { JSDOM } from 'jsdom';

import mockReactFlow from './mock-react-flow';

import { toPng, toSvg } from 'html-to-image';

import WorkflowDiagram from '../js/workflow-diagram/WorkflowDiagram';
import { createWorkflowStore } from '../js/workflow-editor/store';

import { generateImage } from 'jsdom-screenshot';

import fs from 'node:fs/promises';

const { window } = new JSDOM(
  `<html><body><div id="root">x</div></body></html>`
);

const document = window.document;

global.document = document;
global.navigator = {};
// @ts-ignore
global.window = window;

// Map some globals from JS dom to make sure react flow sort of works
global.HTMLElement = window.Element;
global.SVGElement = window.SVGElement;

// hmm, wierd stuff needed for html-to-image
global.HTMLCanvasElement = window.HTMLCanvasElement;
global.HTMLVideoElement = window.HTMLVideoElement;
global.HTMLIFrameElement = window.HTMLIFrameElement;
global.HTMLTextAreaElement = window.HTMLTextAreaElement;
global.HTMLInputElement = window.HTMLInputElement;
global.HTMLSelectElement = window.HTMLSelectElement;
global.HTMLImageElement = window.HTMLImageElement;
global.XMLSerializer = window.XMLSerializer;
global.Image = window.Image;
global.SVGImageElement = window.HTMLImageElement;
global.Element = window.Element;
mockReactFlow();

// first we load a workflow diagram

const root = document.getElementById('root');
// nothing here?
createRoot(root).render(<h1>blah</h1>);

// wait for the render to actually run
// awkward
// setTimeout(() => {
//   console.log(root.textContent);
//   console.log(document.body.outerHTML);
// }, 100);

const model = {
  triggers: [
    {
      id: 't1',
      workflow_id: 'w',
      type: 'webhook',
      enabled: true,
      name: 'Trigger',
      webhook_url: 'www',
      has_auth_method: false,
    },
  ],
  jobs: [
    {
      id: 'n1',
      workflow_id: 'w',
      body: '.',
      enabled: true,
      name: 'Step 1',
    },
  ],
  edges: [
    {
      id: 't1-n1',
      source_trigger_id: 't1',
      target_job_id: 'n1',
      name: 'edge',
    },
  ],
};

// const store = createWorkflowStore(model, () => {});

// createRoot(root).render(<WorkflowDiagram store={store}></WorkflowDiagram>);

setTimeout(async () => {
  /**
   * Ok it's not enough just to take the SVG
   * Some thing gets rendered to SVG, and some things get rendered to HTML
   * The diagram is a mix of both
   * So this simple approach won't work. Dang.
   */
  // const [svg] = document.getElementsByTagName('svg');
  // console.log(svg.outerHTML);
  // await fs.writeFile(__dirname + '/out.svg', svg.outerHTML);

  // TODO OK so why does this break?
  // getComputedStyle is not implemneted.
  console.log(' >>> TO PNG');
  // const dataUrl = await toPng(document.querySelector('.react-flow__viewport'), {
  // const dataUrl = await toPng(document.getElementById('root'), {
  //   // backgroundColor: '#1a365d',
  //   // width: 500,
  //   // height: 500,
  //   // style: {
  //   //   width: 500,
  //   //   height: 500,
  //   //   // TODO need to run a fit then do this
  //   //   transform: `translate(0px, 0px) scale(1)`,
  //   // },
  // });

  // take screenshot
  generateImage();

  console.log('DONE');
  // console.log({ dataUrl });
}, 500);

// // why can't I find the svg in the dom?

// // setTimeout(() => {
// //   const out = fs.createWriteStream(__dirname + '/test.png');
// //   const stream = canvas.createPNGStream();
// //   stream.pipe(out);
// //   out.on('finish', () => console.log('The PNG file was created.'));
// // }, 100);

// // toPng(root).then(function (dataUrl) {
// //   console.log(dataUrl);
// //   // var img = new Image();
// //   // img.src = dataUrl;
// //   // document.body.appendChild(img);
// // });

// toPng(document.querySelector('.react-flow__viewport'), {
//   backgroundColor: '#1a365d',
//   width: 500,
//   height: 500,
//   style: {
//     width: 500,
//     height: 500,
//     // TODO need to run a it then do this)
//     transform: `translate(0px, 0px) scale(1)`,
//   },
// }).then(dataUrl => {
//   console.log(dataUrl);
//   var img = new Image();
//   img.src = dataUrl;
//   document.body.appendChild(img);
// });
