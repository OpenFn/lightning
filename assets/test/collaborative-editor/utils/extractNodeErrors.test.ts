import { describe, it, expect } from "vitest";
import { extractNodeErrors } from "#/collaborative-editor/utils/extractNodeErrors";

describe("extractNodeErrors", () => {
  it("extracts job errors correctly", () => {
    const errors = {
      name: ["workflow name error"], // workflow-level, ignored
      jobs: {
        "job-1": {
          name: ["can't be blank"],
          adaptor: ["Invalid format"],
        },
        "job-2": {
          body: ["must be provided"],
        },
      },
    };

    const result = extractNodeErrors(errors);

    expect(result.jobs["job-1"]).toEqual({
      name: ["can't be blank"],
      adaptor: ["Invalid format"],
    });
    expect(result.jobs["job-2"]).toEqual({
      body: ["must be provided"],
    });
  });

  it("extracts edge errors correctly", () => {
    const errors = {
      edges: {
        "edge-1": {
          condition_expression: ["is invalid"],
          target_job_id: ["must exist"],
        },
      },
    };

    const result = extractNodeErrors(errors);

    expect(result.edges["edge-1"]).toEqual({
      condition_expression: ["is invalid"],
      target_job_id: ["must exist"],
    });
  });

  it("extracts trigger errors correctly", () => {
    const errors = {
      triggers: {
        "trigger-1": {
          enabled: ["must be set"],
        },
      },
    };

    const result = extractNodeErrors(errors);

    expect(result.triggers["trigger-1"]).toEqual({
      enabled: ["must be set"],
    });
  });

  it("handles mixed error types", () => {
    const errors = {
      name: ["workflow-level error"],
      jobs: {
        "job-1": { name: ["error1"] },
      },
      edges: {
        "edge-1": { condition_type: ["error2"] },
      },
      triggers: {
        "trigger-1": { type: ["error3"] },
      },
    };

    const result = extractNodeErrors(errors);

    expect(result.jobs["job-1"]).toBeDefined();
    expect(result.edges["edge-1"]).toBeDefined();
    expect(result.triggers["trigger-1"]).toBeDefined();
  });

  it("handles missing entity types", () => {
    const errors = {
      name: ["workflow error"],
      jobs: {
        "job-1": { name: ["error"] },
      },
      // No edges or triggers
    };

    const result = extractNodeErrors(errors);

    expect(result.jobs["job-1"]).toBeDefined();
    expect(result.edges).toEqual({});
    expect(result.triggers).toEqual({});
  });

  it("returns empty structure for empty errors", () => {
    const result = extractNodeErrors({});

    expect(result).toEqual({
      jobs: {},
      edges: {},
      triggers: {},
    });
  });

  it("handles errors with no entity errors", () => {
    const errors = {
      name: ["can't be blank"],
      concurrency: ["must be at least 1"],
    };

    const result = extractNodeErrors(errors);

    expect(result).toEqual({
      jobs: {},
      edges: {},
      triggers: {},
    });
  });
});
