import React, { useState } from 'react';
import Docs from '@openfn/adaptor-docs';

type DocsProps = {
  adaptor: string; // name of the adaptor to load. aka specfier.
}

export default ({ adaptor }: DocsProps) => <Docs specifier={adaptor} />;

// export default ({ adaptor }: DocsProps) => {
//   const [d] = useState(adaptor);
//   return <h1>{d}</h1>
// }