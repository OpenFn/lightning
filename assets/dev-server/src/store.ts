import create from 'zustand';

const useStore = create(set => {
  console.log('CREATE STORE');
  return {
    jobs: [{ id: 'a' }, { id: 'b' }, { id: 'c' }],
    triggers: [{ id: 'z' }],
    edges: [
      { id: 'z-a', source_trigger: 'z', target_job: 'a' },
      { id: 'a-b', source_job: 'a', target_job: 'b' },
      { id: 'a-c', source_job: 'a', target_job: 'c' },
    ],
  };
});

export default useStore;
