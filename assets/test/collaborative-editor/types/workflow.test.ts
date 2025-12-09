import { describe, it, expect } from 'vitest';

import { WorkflowSchema } from '#/collaborative-editor/types/workflow';

describe('WorkflowSchema', () => {
  describe('name validation', () => {
    it('should reject names ending with _del followed by digits', () => {
      const invalidData = {
        id: '123e4567-e89b-12d3-a456-426614174000',
        name: 'My Workflow_del0001',
        lock_version: 1,
        deleted_at: null,
      };

      const result = WorkflowSchema.safeParse(invalidData);
      expect(result.success).toBe(false);
    });

    it('should reject names ending with _del without digits', () => {
      const invalidData = {
        id: '123e4567-e89b-12d3-a456-426614174000',
        name: 'My Workflow_del',
        lock_version: 1,
        deleted_at: null,
      };

      const result = WorkflowSchema.safeParse(invalidData);
      expect(result.success).toBe(false);
    });

    it('should reject names ending with _del followed by 3 digits', () => {
      const invalidData = {
        id: '123e4567-e89b-12d3-a456-426614174000',
        name: 'My Workflow_del123',
        lock_version: 1,
        deleted_at: null,
      };

      const result = WorkflowSchema.safeParse(invalidData);
      expect(result.success).toBe(false);
    });

    it('should reject names ending with _del followed by 5 digits', () => {
      const invalidData = {
        id: '123e4567-e89b-12d3-a456-426614174000',
        name: 'My Workflow_del12345',
        lock_version: 1,
        deleted_at: null,
      };

      const result = WorkflowSchema.safeParse(invalidData);
      expect(result.success).toBe(false);
    });

    it('should allow normal workflow names', () => {
      const validData = {
        id: '123e4567-e89b-12d3-a456-426614174000',
        name: 'My Workflow',
        lock_version: 1,
        deleted_at: null,
      };

      const result = WorkflowSchema.safeParse(validData);
      expect(result.success).toBe(true);
    });

    it('should allow names with _del in the middle', () => {
      const validData = {
        id: '123e4567-e89b-12d3-a456-426614174000',
        name: 'My_del_Workflow',
        lock_version: 1,
        deleted_at: null,
      };

      const result = WorkflowSchema.safeParse(validData);
      expect(result.success).toBe(true);
    });

    it('should reject multiple invalid formats', () => {
      const testCases = [
        'Test_del0001',
        'Workflow_del9999',
        'Another Workflow_del0000',
        'Name_del',
        'Workflow_del1',
      ];

      testCases.forEach(name => {
        const data = {
          id: '123e4567-e89b-12d3-a456-426614174000',
          name,
          lock_version: 1,
          deleted_at: null,
        };

        const result = WorkflowSchema.safeParse(data);
        expect(result.success).toBe(false);
      });
    });
  });
});
