import * as Y from "yjs";
import { create } from "zustand";
import { devtools, subscribeWithSelector } from "zustand/middleware";
import { immer } from "zustand/middleware/immer";
import type { Workflow, YjsBridge } from "../types";

// Factory function for creating stores with Y.js dependencies
export const createWorkflowStore = () => {
  let yjsBridge: YjsBridge | null = null;

  return create<Workflow.Store>()(
    devtools(
      subscribeWithSelector(
        immer((set, _get) => ({
          // Initial state
          workflow: null,
          jobs: [],
          edges: [],
          triggers: [],
          selectedJobId: null,
          enabled: null,

          // Actions
          selectJob: (jobId: string | null) => {
            set({ selectedJobId: jobId });
          },

          // Method to connect Yjs bridge after provider setup
          connectToYjs: (bridge: YjsBridge) => {
            yjsBridge = bridge;
          },

          setEnabled: (enabled: boolean) => {
            if (yjsBridge) {
              yjsBridge.setEnabled(enabled);
            }
          },

          getJobBodyYText: (jobId: string) => {
            if (yjsBridge) {
              const yjsJob = yjsBridge.getYjsJob(jobId);
              return yjsJob?.get("body") as Y.Text;
            }
            return null;
          },
          // Y.js-backed job actions
          updateJob: (jobId, updates) => {
            if (yjsBridge) {
              const yjsJob = yjsBridge.getYjsJob(jobId);
              if (yjsJob) {
                Object.entries(updates).forEach(([key, value]) => {
                  if (key === "body" && typeof value === "string") {
                    const ytext = yjsJob.get("body") as Y.Text;
                    if (ytext) {
                      ytext.delete(0, ytext.length);
                      ytext.insert(0, value);
                    }
                  } else {
                    yjsJob.set(key, value);
                  }
                });
              }
            }
          },

          addJob: (job) => {
            if (yjsBridge && job.id && job.name) {
              const jobMap = new Y.Map();
              jobMap.set("id", job.id);
              jobMap.set("name", job.name);
              if (job.body) jobMap.set("body", new Y.Text(job.body));
              yjsBridge.jobsArray.push([jobMap]);
            }
          },

          removeJob: (jobId) => {
            if (yjsBridge) {
              const jobs = yjsBridge.jobsArray.toArray();
              const index = jobs.findIndex((job) => job.get("id") === jobId);
              if (index >= 0) {
                yjsBridge.jobsArray.delete(index, 1);
              }
            }
          },

          // Convenience actions for direct Y.js operations
          updateJobName: (id, name) => {
            if (yjsBridge) {
              const yjsJob = yjsBridge.getYjsJob(id);
              if (yjsJob) {
                yjsJob.set("name", name);
              }
            }
          },

          updateJobBody: (id, body) => {
            if (yjsBridge) {
              const ytext = yjsBridge.getJobBodyText(id);
              if (ytext) {
                ytext.delete(0, ytext.length);
                ytext.insert(0, body);
              }
            }
          },
        })),
      ),
    ),
  );
};
