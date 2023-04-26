import create from 'zustand';
import { immer } from 'zustand/middleware/immer';

const useStore = create(
  immer(set => {
    console.log('CREATE STORE');
    return {
      // Basic model
      workflow: {
        jobs: [],
        triggers: [],
        edges: [],
      },

      // Set a whole new workflow
      setWorkflow: workflow => set({ workflow }),
    };
  })
);

export default useStore;
