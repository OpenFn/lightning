# #4718: Standardize project and workflow export to match portability spec

[Github](https://github.com/OpenFn/lightning/issues/4718)

**Status:** open
**Created:** 2026-05-07T10:42:32Z
**Updated:** 2026-05-07T11:38:36Z
**Assignee:** josephjclark
**Labels:**

In order to line up the portability spec across our tools, we need to ensure:

1. Exporting a project should download a CLI compatible stateless project file (as described in [#1398 Project: allow me to write a new project.yaml file without UUIDs](https://github.com/OpenFn/kit/issues/1398))
2. Exporting (and importing) a workflow should use the CLI's workflow format (as described in [#1117 Different workflow formats in CLI and Lightning (breaks workflow import!)](https://github.com/OpenFn/kit/issues/1117))

If we do these things, then file formats across the CLI and lightning will _finally_ be fully aligned and interopable and compatible. And we can make the Portability Spec really mean something,

Additional: when exporting workflow and project files from the app, let users choose the format.

## Comments

### josephjclark — 2026-05-07T11:09:24Z

templates are also affected by this!

look at `canonical_template.yaml`
