import React from 'react';

export const FooContext = React.createContext<number | undefined>(undefined);
FooContext.displayName = 'FooContext';
