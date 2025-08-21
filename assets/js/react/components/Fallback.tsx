import type { FallbackProps } from 'react-error-boundary';

export type { FallbackProps };

const renderStyle = "border border-gray-300 bg-[repeating-linear-gradient(45deg,theme(colors.gray.200)_0_12px,theme(colors.gray.100)_12px_24px)] dark:border-gray-600 dark:bg-[repeating-linear-gradient(45deg,theme(colors.gray.700)_0_12px,theme(colors.gray.800)_12px_24px)]"

export const Fallback = ({ error, resetErrorBoundary }: FallbackProps) => {
  return <>
    <div className={'w-full h-full ' + renderStyle}>
    </div>
    <div role="alert" className='z-50 fixed top-0 right-0 bottom-0 left-0 flex items-center justify-center bg-red-100/50'>
      <div className='bg-white rounded-lg p-4 w-[512px] h-auto shadow'>
        <h2 className='text-xl mb-3 flex items-center gap-2'> <span className='hero-exclamation-circle text-yellow-500 size-6'></span> Oops, something went wrong</h2>
        <p>An error occurred while rendering some part of the application.</p>
        <p>You can either retry rendering the content or reloading the entire page. </p>
        <pre className='rounded p-1 text-red-400 my-4 py-4 text-sm overflow-auto font-mono bg-gray-100 border'>
          {error instanceof Error ? error.message : String(error)}
        </pre>
        <div className="mt-2 flex gap-2">
          <button
            type="button"
            className="rounded-md text-sm font-semibold shadow-xs phx-submit-loading:opacity-75 bg-primary-600 hover:bg-primary-500 text-white disabled:bg-primary-300 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600 px-2 py-1 flex items-center gap-1"
            onClick={resetErrorBoundary}
          >
            <span className="hero-tv w-4 h-4"></span>  Retry
          </button>
          <button
            type="button"
            className="rounded-md text-sm font-semibold shadow-xs phx-submit-loading:opacity-75 bg-primary-600 hover:bg-primary-500 text-white disabled:bg-primary-300 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600 px-2 py-1 flex items-center gap-1"
            onClick={() => { window.location.reload() }}
          >
            <span className="hero-arrow-path w-4 h-4"></span>  Reload
          </button>
        </div>
      </div>
    </div >
  </>
}
