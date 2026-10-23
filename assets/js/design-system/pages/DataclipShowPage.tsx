import {
  DataclipShowPage as DesignSystemDataclipShowPage,
  type DataclipShowPageProps,
} from '@openfn/ui';
import { useEffect, useState } from 'react';

import { fetchDataclipBody } from '../dataclip-body';
import { designSystemPage } from '../page';

// Sets Monaco's workers and loader before the page's viewers mount, so they
// use Lightning's bundled Monaco and not the CDN.
import '#/monaco';

/** What DataclipLive.Show puts in `data-props`: the page's props minus the body. */
export type Props = Omit<DataclipShowPageProps, 'body'>;

/**
 * The design system's dataclip page, fed by DataclipLive.Show. The island
 * fetches the body in the browser, as the old viewer did; a wiped dataclip
 * has none to fetch.
 */
export const DataclipShowPage = designSystemPage(
  'DataclipShowPage',
  DesignSystemDataclipShowPage,
  ['/projects/:project_id/dataclips/:id/show'],
  (props: Props) => {
    const { id, wipedAt } = props.dataclip;
    const [body, setBody] = useState<{ id: string; text: string }>();

    useEffect(() => {
      if (wipedAt !== null) return;
      let current = true;
      void fetchDataclipBody(id).then(text => current && setBody({ id, text }));
      return () => {
        current = false;
      };
    }, [id, wipedAt]);

    return { ...props, body: body?.id === id ? body.text : undefined };
  }
);
