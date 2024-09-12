const j = (id, props = {}) => ({
  id,
  name: id,
  adaptor: 'common',
  expression: 'fn(s => s)',
  ...props,
});

const e = (source: string, target: string, props = {}) => ({
  id: `${source}-${target}`,
  source_job_id: source,
  target_job_id: target,
  ...props,
});

const workflows = {};

const add = (id, items) => {
  // add a default trigger
  const triggers = [
    {
      id: 'trigger',
      type: 'webhook',
    },
  ];

  const edges = [];
  const jobs = [];

  let firstJob;
  items.forEach(i => {
    if (i.source_job_id) {
      edges.push(i);
    } else {
      if (!firstJob) {
        firstJob = i;
      }
      jobs.push(i);
    }
  });

  // add an edge to the trigger
  if (firstJob) {
    edges.push({
      id: 'trigger-first',
      source_trigger_id: triggers[0].id,
      target_job_id: firstJob.id,
    });
  }

  workflows[id] = {
    id,
    edges,
    jobs,
    triggers,
  };
};

// random fisher yates pulled offline
const shuffle = array => {
  for (let i = array.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    const temp = array[i];
    array[i] = array[j];
    array[j] = temp;
  }
  return array;
};

add('aisha', [
  j('root'),
  j('orphan'),
  j('create encounter'),
  j('trigger a thing'),
  j('create an observation'),
  j('create a medication'),
  j('create a condition'),
  j('update encounter'),
  e('root', 'create encounter'),
  j('send medication id'),
  j('create a MedicationRequest'),
  e('create encounter', 'trigger a thing'),
  e('create encounter', 'create a medication'),
  e('create encounter', 'create an observation'),
  e('create encounter', 'create a condition'),
  e('create an observation', 'update encounter'),
  e('create a condition', 'update encounter'),
  e('create a medication', 'send medication id'),
  e('create a medication', 'create a MedicationRequest'),
  e('send medication id', 'create a MedicationRequest'),
]);

// add(
//   'aisha-shuffled',
//   // TODO this doesn't acutally work without a refresh. We don't have a means to re-shuffle
//   // And anyway shuffling kind of breaks the model, because we create bad edges.
//   shuffle([
//     j('root'),
//     j('orphan'),
//     j('create encounter'),
//     j('trigger a thing'),
//     j('create an observation'),
//     j('create a medication'),
//     j('create a condition'),
//     j('update encounter'),
//     e('root', 'create encounter'),
//     j('send medication id'),
//     j('create a MedicationRequest'),
//     e('create encounter', 'trigger a thing'),
//     e('create encounter', 'create a medication'),
//     e('create encounter', 'create an observation'),
//     e('create encounter', 'create a condition'),
//     e('create an observation', 'update encounter'),
//     e('create a condition', 'update encounter'),
//     e('create a medication', 'send medication id'),
//     e('create a medication', 'create a MedicationRequest'),
//     e('send medication id', 'create a MedicationRequest'),
//   ])
// );

add('aisha-simplified?', [
  j('create a medication'),
  j('send medication id'),
  j('create a MedicationRequest'),
  e('create a medication', 'send medication id'),
  e('create a medication', 'create a MedicationRequest'),
  e('send medication id', 'create a MedicationRequest'),
]);

add('tangle', [
  j('a'),

  j('b'),
  j('c'),

  j('d'),
  j('e'),
  j('f'),

  j('v'),
  j('w'),
  j('x'),
  j('y'),
  j('z'),

  e('a', 'b'),
  e('a', 'c'),
  e('a', 'z'),
  e('a', 'f'),
  e('a', 'y'),

  e('b', 'z'),
  e('b', 'w'),
  e('b', 'x'),
  e('b', 'y'),

  e('c', 'd'),
  e('c', 'e'),
  e('c', 'f'),

  e('d', 'v'),
  e('d', 'w'),
  e('d', 'x'),
  e('d', 'y'),
  e('d', 'z'),

  e('x', 'y'),
]);

add('c5', [
  j('a'),

  j('b'),
  j('c'),

  j('d'),
  j('e'),
  j('f'),

  j('v'),
  j('w'),
  j('x'),
  j('y'),
  j('z'),

  e('a', 'b'),
  e('a', 'c'),
  e('c', 'd'),
  e('c', 'e'),
  e('c', 'f'),

  e('d', 'v'),
  e('d', 'w'),
  e('d', 'x'),
  e('d', 'y'),
  e('d', 'z'),
]);

add('overlap-1', [
  j('a'),
  j('b'),
  j('d'),
  e('a', 'b'),
  e('b', 'd'),
  e('b', 'c'), // this edge seems to cause a problem even though c doesn't exist!
  e('a', 'd'),
]);

add('overlap-2', [
  j('a'),
  j('b'),
  j('c'),
  j('d'),
  j('e'),
  e('a', 'b'),
  e('b', 'd'),
  e('b', 'c'),
  e('a', 'd'),

  e('d', 'e'),
]);

add('overlap-3', [
  j('a'),
  j('b'),
  j('c'),
  j('d'),
  e('a', 'b'),
  e('b', 'd'),
  e('b', 'c'),
  e('a', 'd'),
]);

add('c4', [
  j('a'),
  j('b'),
  j('c'),
  j('d'),
  j('e'),
  j('f'),
  e('a', 'b'),
  e('a', 'c'),
  e('c', 'd'),
  e('c', 'e'),
  e('c', 'f'),
]);

add('c3', [
  j('a'),
  j('b'),
  j('c'),
  j('d'),
  e('a', 'b'),
  e('a', 'c'),
  e('c', 'd'),
]);

add('simple-1', [j('a'), j('b'), j('c'), e('a', 'b'), e('a', 'c')]);

add('simple-2', [j('a')]);

add('orphans', [j('a'), j('x'), j('y'), e('x', 'y')]);

// hack for re-run
add('empty', []);

console.log(workflows);

export default workflows;
