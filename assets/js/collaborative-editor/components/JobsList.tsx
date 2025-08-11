/**
 * JobsList - List of jobs with selection capabilities
 */

import type React from "react";
import { useWorkflowStore } from "../contexts/WorkflowStoreProvider";
import { JobItem } from "./JobItem";

export const JobsList: React.FC = () => {
	const { jobs, selectedJobId, selectJob } = useWorkflowStore((state) => ({
		jobs: state.jobs,
		selectedJobId: state.selectedJobId,
		selectJob: state.selectJob,
	}));

	console.log("JobsList: selectedJobId", selectedJobId);
	console.log("JobsList: jobs", jobs);

	const clearSelection = () => {
		selectJob(null);
	};

	return (
		<div className="mb-6">
			<div className="flex items-center justify-between mb-4">
				<h3 className="font-semibold text-gray-900">Jobs ({jobs.length})</h3>
				{selectedJobId && (
					<button
						onClick={clearSelection}
						className="text-sm text-blue-600 hover:text-blue-800 underline"
					>
						Clear Selection
					</button>
				)}
			</div>

			{jobs.length === 0 ? (
				<div className="text-center py-12 text-gray-500">
					<svg
						className="w-12 h-12 mx-auto mb-3 text-gray-300"
						fill="none"
						stroke="currentColor"
						viewBox="0 0 24 24"
					>
						<path
							strokeLinecap="round"
							strokeLinejoin="round"
							strokeWidth={2}
							d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
						/>
					</svg>
					<p>No jobs in this workflow yet.</p>
					<p className="text-sm mt-1">
						Jobs will appear here when they are added to the workflow.
					</p>
				</div>
			) : (
				<div className="space-y-3">
					{jobs.map((job, index) => (
						<JobItem key={job.id} job={job} index={index} />
					))}
				</div>
			)}
		</div>
	);
};
