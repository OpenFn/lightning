const workflows = {
  chart1: {
    id: 'chart1',
    jobs: [
      {
        id: 'a',
        name: 'Do the thing',
        adaptor: 'common',
        expression: 'fn(s => s)',
      },
      {
        id: 'b',
        adaptor: 'salesforce',
        expression: 'fn(s => s)',
      },
      {
        id: 'c',
        adaptor: 'http',
        expression: 'fn(s => s)',
      },
    ],
    triggers: [
      {
        id: 'z',
        type: 'cron',
        cronExpression: '0 0 0',
      },
    ],
    edges: [
      {
        id: 'z-a',
        name: 'on success',
        source_trigger_id: 'z',
        target_job_id: 'a',
      },
      {
        id: 'a-b',
        name: 'on success',
        source_job_id: 'a',
        target_job_id: 'b',
      },
      {
        id: 'a-c',
        name: 'on success',
        source_job_id: 'a',
        target_job_id: 'c',
      },
    ],
  },
  chart2: {
    id: 'chart2',
    jobs: [{ id: 'a' }],
    triggers: [{ id: 'z' }],
    edges: [{ id: 'z-a', source_trigger_id: 'z', target_job_id: 'a' }],
  },
  chart3: {
    id: 'chart3',
    jobs: [
      { id: 'a' },
      { id: 'b', label: 'this is a very long node name oh yes' },
      { id: 'c' },
    ],
    triggers: [],
    edges: [
      // { id: 'z-a', source_trigger_id: 'z', target_job_id: 'a' },
      { id: 'a-b', source_job: 'a', target_job_id: 'b' },
      { id: 'b-c', source_job: 'b', target_job_id: 'c' },
    ],
  },
};

export default workflows;
