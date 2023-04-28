import React from 'react';

const Empty = ({ adaptor }: { adaptor: string; error }) => (
  <div>
    <p className="block m-2">{`No metadata found for ${adaptor}`}</p>
    <p className="block m-2">
      This adaptor does not support magic functions yet.
    </p>
  </div>
);

export default Empty;
