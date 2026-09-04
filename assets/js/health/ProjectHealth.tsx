import { Subtitle } from './Subtitle';
import type { Outcomes } from './types';
import { useHealthQuery } from './useHealthQuery';

/**
 * Project health page: a 30-day summary of the work orders across every
 * workflow in the project.
 *
 * The counts come from the same aggregation the workflow health page uses,
 * scoped to the project instead of one workflow, so the two pages cannot
 * disagree about what a work order is or when it finished.
 *
 * No charts yet — the page exists so the route, the endpoint and the mount
 * point are proven end to end before we choose which chart lands first.
 *
 * Mounted via `phx-hook="ReactComponent"`, so props arrive as the element's
 * raw kebab-case `data-*` attributes and are always strings.
 */

interface ProjectHealthProps {
  'data-project-id': string;
  'data-project-name': string;
}

export const ProjectHealth = (props: ProjectHealthProps) => (
  <ProjectHealthContent
    projectId={props['data-project-id']}
    projectName={props['data-project-name']}
  />
);

interface ProjectHealthContentProps {
  projectId: string;
  projectName: string;
}

export const ProjectHealthContent = ({
  projectId,
  projectName,
}: ProjectHealthContentProps) => {
  const outcomes = useHealthQuery<Outcomes>(
    `/api/projects/${projectId}/health/outcomes`
  );

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-2xl font-semibold text-gray-900">{projectName}</h1>
        {/* The subtitle is the whole page for now, so its failure has to be
            visible here rather than swallowed as a missing line. */}
        {outcomes.error ? (
          <p className="text-sm text-red-700">{outcomes.error}</p>
        ) : (
          <Subtitle outcomes={outcomes.data} />
        )}
      </div>
    </div>
  );
};
