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
  edges.push({
    id: 'trigger-first',
    source_trigger_id: triggers[0].id,
    target_job_id: firstJob.id,
  });

  workflows[id] = {
    id,
    edges,
    jobs,
    triggers,
  };
};

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

console.log(workflows);

export default workflows;
