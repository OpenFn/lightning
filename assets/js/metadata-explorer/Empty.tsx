import React from 'react';

const Empty = ({ adaptor }: { adaptor: string, error }) => (<div>
  <p className="text-sm mb-4">{`No metadata found for ${adaptor}`}</p>
  <p  className="text-sm mb-4">This adaptor does not support magic functions yet.</p>
</div>)

export default Empty;