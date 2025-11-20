import * as z from 'zod';

export const uuidSchema = z.uuidv4({ message: 'Invalid UUID format' });

export const isoDateTimeSchema = z.iso.datetime({
  message: 'Invalid datetime format',
});
