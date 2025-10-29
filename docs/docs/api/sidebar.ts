import type { SidebarsConfig } from "@docusaurus/plugin-content-docs";

const sidebar: SidebarsConfig = {
  apisidebar: [
    {
      type: "doc",
      id: "api/lightning-api",
    },
    {
      type: "category",
      label: "Projects",
      link: {
        type: "doc",
        id: "api/projects",
      },
      items: [
        {
          type: "doc",
          id: "api/list-projects",
          label: "List all accessible projects",
          className: "api-method get",
        },
        {
          type: "doc",
          id: "api/get-project",
          label: "Get project by ID",
          className: "api-method get",
        },
      ],
    },
    {
      type: "category",
      label: "Workflows",
      link: {
        type: "doc",
        id: "api/workflows",
      },
      items: [
        {
          type: "doc",
          id: "api/list-project-workflows",
          label: "List workflows for a project",
          className: "api-method get",
        },
        {
          type: "doc",
          id: "api/list-workflows",
          label: "List all accessible workflows",
          className: "api-method get",
        },
        {
          type: "doc",
          id: "api/create-workflow",
          label: "Create a new workflow",
          className: "api-method post",
        },
        {
          type: "doc",
          id: "api/get-workflow",
          label: "Get workflow by ID",
          className: "api-method get",
        },
        {
          type: "doc",
          id: "api/update-workflow",
          label: "Update an existing workflow",
          className: "api-method patch",
        },
      ],
    },
    {
      type: "category",
      label: "Jobs",
      link: {
        type: "doc",
        id: "api/jobs",
      },
      items: [
        {
          type: "doc",
          id: "api/list-project-jobs",
          label: "List jobs for a project",
          className: "api-method get",
        },
      ],
    },
    {
      type: "category",
      label: "Credentials",
      link: {
        type: "doc",
        id: "api/credentials",
      },
      items: [
        {
          type: "doc",
          id: "api/list-credentials",
          label: "List credentials",
          className: "api-method get",
        },
        {
          type: "doc",
          id: "api/create-credential",
          label: "Create a new credential",
          className: "api-method post",
        },
        {
          type: "doc",
          id: "api/delete-credential",
          label: "Delete a credential",
          className: "api-method delete",
        },
      ],
    },
    {
      type: "category",
      label: "Work Orders",
      link: {
        type: "doc",
        id: "api/work-orders",
      },
      items: [
        {
          type: "doc",
          id: "api/list-project-work-orders",
          label: "List work orders for a project",
          className: "api-method get",
        },
        {
          type: "doc",
          id: "api/get-work-order",
          label: "Get work order by ID",
          className: "api-method get",
        },
      ],
    },
    {
      type: "category",
      label: "Runs",
      link: {
        type: "doc",
        id: "api/runs",
      },
      items: [
        {
          type: "doc",
          id: "api/list-project-runs",
          label: "List runs for a project",
          className: "api-method get",
        },
        {
          type: "doc",
          id: "api/get-run",
          label: "Get run by ID",
          className: "api-method get",
        },
      ],
    },
    {
      type: "category",
      label: "Log Lines",
      link: {
        type: "doc",
        id: "api/log-lines",
      },
      items: [
        {
          type: "doc",
          id: "api/list-log-lines",
          label: "List log lines",
          className: "api-method get",
        },
      ],
    },
    {
      type: "category",
      label: "Provisioning",
      link: {
        type: "doc",
        id: "api/provisioning",
      },
      items: [
        {
          type: "doc",
          id: "api/create-provision",
          label: "Create provisioned project",
          className: "api-method post",
        },
      ],
    },
    {
      type: "category",
      label: "Registration",
      link: {
        type: "doc",
        id: "api/registration",
      },
      items: [
        {
          type: "doc",
          id: "api/register-user",
          label: "Register a new user",
          className: "api-method post",
        },
      ],
    },
  ],
};

export default sidebar.apisidebar;
