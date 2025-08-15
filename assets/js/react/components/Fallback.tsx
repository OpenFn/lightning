import type { FallbackProps } from "react-error-boundary";
export type { FallbackProps };

export const Fallback = ({ error }: FallbackProps) => {
	const stack = error.stack || "";

	return (
		<div className="min-h-screen flex items-center justify-center">
			<div
				role="alert"
				className="p-4 bg-red-50 border border-red-200 rounded-md"
			>
				<div className="sm:flex sm:items-start">
					<div className="mx-auto flex size-12 shrink-0 items-center justify-center rounded-full bg-red-100 sm:mx-0 sm:size-10">
						<div className="hero-exclamation-triangle h-6 w-6 text-red-600" />
					</div>
					<div className="mt-3 text-center sm:mt-0 sm:ml-4 sm:text-left">
						<h3
							id="dialog-title"
							className="text-base font-semibold text-gray-900"
						>
							Development Error
						</h3>
						<div className="mt-2 space-y-2">
							<div>
								<h4 className="font-medium text-gray-900">Error Message:</h4>
								<pre className="text-sm text-red-600 bg-red-100 p-2 rounded overflow-x-auto">
									{error instanceof Error ? error.message : String(error)}
								</pre>
							</div>

							{error instanceof Error && stack && (
								<div>
									<h4 className="font-medium text-gray-900">Stack Trace:</h4>
									<pre className="text-xs text-gray-700 bg-gray-100 p-2 rounded overflow-x-auto whitespace-pre-wrap">
										{stack}
									</pre>
								</div>
							)}
						</div>
					</div>
				</div>
			</div>
		</div>
	);
};
