/**
 * normalizePointer Tests
 *
 * Tests for coordinate transformation functions used in collaborative cursors:
 * - normalizePointerPosition: Converts screen coordinates to flow coordinates
 * - denormalizePointerPosition: Converts flow coordinates back to screen coordinates
 *
 * These functions handle zoom and pan transformations for cursor positions
 * in the ReactFlow canvas.
 */

import { describe, expect, test } from 'vitest';
import type { Transform } from '@xyflow/react';

import {
  normalizePointerPosition,
  denormalizePointerPosition,
} from '../../../../js/collaborative-editor/components/diagram/normalizePointer';

describe('normalizePointer', () => {
  describe('normalizePointerPosition', () => {
    test('converts screen coordinates to flow coordinates with no transform', () => {
      const transform: Transform = [0, 0, 1]; // no pan, no zoom
      const screenPos = { x: 100, y: 200 };

      const result = normalizePointerPosition(screenPos, transform);

      expect(result).toEqual({ x: 100, y: 200 });
    });

    test('handles positive pan offset', () => {
      const transform: Transform = [50, 30, 1]; // pan right 50, down 30
      const screenPos = { x: 100, y: 200 };

      const result = normalizePointerPosition(screenPos, transform);

      // When canvas is panned right 50, a screen position of 100
      // corresponds to flow position of 50
      expect(result).toEqual({ x: 50, y: 170 });
    });

    test('handles negative pan offset', () => {
      const transform: Transform = [-50, -30, 1]; // pan left 50, up 30
      const screenPos = { x: 100, y: 200 };

      const result = normalizePointerPosition(screenPos, transform);

      expect(result).toEqual({ x: 150, y: 230 });
    });

    test('handles zoom scaling', () => {
      const transform: Transform = [0, 0, 2]; // 2x zoom
      const screenPos = { x: 100, y: 200 };

      const result = normalizePointerPosition(screenPos, transform);

      // With 2x zoom, screen position 100 corresponds to flow position 50
      expect(result).toEqual({ x: 50, y: 100 });
    });

    test('handles zoom out (scale < 1)', () => {
      const transform: Transform = [0, 0, 0.5]; // 0.5x zoom (zoomed out)
      const screenPos = { x: 100, y: 200 };

      const result = normalizePointerPosition(screenPos, transform);

      // With 0.5x zoom, screen position 100 corresponds to flow position 200
      expect(result).toEqual({ x: 200, y: 400 });
    });

    test('handles combined pan and zoom', () => {
      const transform: Transform = [50, 30, 2]; // pan right 50, down 30, 2x zoom
      const screenPos = { x: 150, y: 230 };

      const result = normalizePointerPosition(screenPos, transform);

      // First subtract pan: (150-50, 230-30) = (100, 200)
      // Then divide by scale: (100/2, 200/2) = (50, 100)
      expect(result).toEqual({ x: 50, y: 100 });
    });

    test('handles origin point (0, 0)', () => {
      const transform: Transform = [100, 50, 1.5];
      const screenPos = { x: 0, y: 0 };

      const result = normalizePointerPosition(screenPos, transform);

      expect(result.x).toBeCloseTo(-66.67, 1);
      expect(result.y).toBeCloseTo(-33.33, 1);
    });

    test('handles large coordinates', () => {
      const transform: Transform = [0, 0, 1];
      const screenPos = { x: 10000, y: 10000 };

      const result = normalizePointerPosition(screenPos, transform);

      expect(result).toEqual({ x: 10000, y: 10000 });
    });

    test('handles negative screen coordinates', () => {
      const transform: Transform = [0, 0, 1];
      const screenPos = { x: -50, y: -100 };

      const result = normalizePointerPosition(screenPos, transform);

      expect(result).toEqual({ x: -50, y: -100 });
    });
  });

  describe('denormalizePointerPosition', () => {
    test('converts flow coordinates to screen coordinates with no transform', () => {
      const transform: Transform = [0, 0, 1];
      const flowPos = { x: 100, y: 200 };

      const result = denormalizePointerPosition(flowPos, transform);

      expect(result).toEqual({ x: 100, y: 200 });
    });

    test('handles positive pan offset', () => {
      const transform: Transform = [50, 30, 1];
      const flowPos = { x: 100, y: 200 };

      const result = denormalizePointerPosition(flowPos, transform);

      // Flow position 100 with pan right 50 = screen position 150
      expect(result).toEqual({ x: 150, y: 230 });
    });

    test('handles negative pan offset', () => {
      const transform: Transform = [-50, -30, 1];
      const flowPos = { x: 100, y: 200 };

      const result = denormalizePointerPosition(flowPos, transform);

      expect(result).toEqual({ x: 50, y: 170 });
    });

    test('handles zoom scaling', () => {
      const transform: Transform = [0, 0, 2];
      const flowPos = { x: 100, y: 200 };

      const result = denormalizePointerPosition(flowPos, transform);

      // Flow position 100 with 2x zoom = screen position 200
      expect(result).toEqual({ x: 200, y: 400 });
    });

    test('handles zoom out (scale < 1)', () => {
      const transform: Transform = [0, 0, 0.5];
      const flowPos = { x: 100, y: 200 };

      const result = denormalizePointerPosition(flowPos, transform);

      // Flow position 100 with 0.5x zoom = screen position 50
      expect(result).toEqual({ x: 50, y: 100 });
    });

    test('handles combined pan and zoom', () => {
      const transform: Transform = [50, 30, 2];
      const flowPos = { x: 50, y: 100 };

      const result = denormalizePointerPosition(flowPos, transform);

      // First multiply by scale: (50*2, 100*2) = (100, 200)
      // Then add pan: (100+50, 200+30) = (150, 230)
      expect(result).toEqual({ x: 150, y: 230 });
    });

    test('handles origin point (0, 0)', () => {
      const transform: Transform = [100, 50, 1.5];
      const flowPos = { x: 0, y: 0 };

      const result = denormalizePointerPosition(flowPos, transform);

      expect(result).toEqual({ x: 100, y: 50 });
    });

    test('handles large coordinates', () => {
      const transform: Transform = [0, 0, 1];
      const flowPos = { x: 10000, y: 10000 };

      const result = denormalizePointerPosition(flowPos, transform);

      expect(result).toEqual({ x: 10000, y: 10000 });
    });

    test('handles negative flow coordinates', () => {
      const transform: Transform = [0, 0, 1];
      const flowPos = { x: -50, y: -100 };

      const result = denormalizePointerPosition(flowPos, transform);

      expect(result).toEqual({ x: -50, y: -100 });
    });
  });

  describe('round-trip transformations', () => {
    test('normalize then denormalize returns original position', () => {
      const transform: Transform = [50, 30, 1.5];
      const original = { x: 123.45, y: 678.9 };

      const normalized = normalizePointerPosition(original, transform);
      const result = denormalizePointerPosition(normalized, transform);

      expect(result.x).toBeCloseTo(original.x, 10);
      expect(result.y).toBeCloseTo(original.y, 10);
    });

    test('denormalize then normalize returns original position', () => {
      const transform: Transform = [100, -50, 0.75];
      const original = { x: 456.78, y: 123.45 };

      const denormalized = denormalizePointerPosition(original, transform);
      const result = normalizePointerPosition(denormalized, transform);

      expect(result.x).toBeCloseTo(original.x, 10);
      expect(result.y).toBeCloseTo(original.y, 10);
    });

    test('round-trip with extreme zoom', () => {
      const transform: Transform = [-200, 300, 5];
      const original = { x: 999.99, y: -555.55 };

      const normalized = normalizePointerPosition(original, transform);
      const result = denormalizePointerPosition(normalized, transform);

      expect(result.x).toBeCloseTo(original.x, 10);
      expect(result.y).toBeCloseTo(original.y, 10);
    });

    test('round-trip with very small zoom', () => {
      const transform: Transform = [10, 20, 0.1];
      const original = { x: 42.42, y: 84.84 };

      const normalized = normalizePointerPosition(original, transform);
      const result = denormalizePointerPosition(normalized, transform);

      expect(result.x).toBeCloseTo(original.x, 8);
      expect(result.y).toBeCloseTo(original.y, 8);
    });
  });

  describe('edge cases', () => {
    test('handles zero zoom gracefully (division by zero)', () => {
      const transform: Transform = [0, 0, 0];
      const screenPos = { x: 100, y: 200 };

      const result = normalizePointerPosition(screenPos, transform);

      // Division by zero should result in Infinity
      expect(result.x).toBe(Infinity);
      expect(result.y).toBe(Infinity);
    });

    test('handles very small scale values', () => {
      const transform: Transform = [0, 0, 0.001];
      const screenPos = { x: 1, y: 1 };

      const result = normalizePointerPosition(screenPos, transform);

      expect(result.x).toBe(1000);
      expect(result.y).toBe(1000);
    });

    test('handles very large scale values', () => {
      const transform: Transform = [0, 0, 1000];
      const screenPos = { x: 1000, y: 1000 };

      const result = normalizePointerPosition(screenPos, transform);

      expect(result.x).toBe(1);
      expect(result.y).toBe(1);
    });

    test('handles fractional pixel coordinates', () => {
      const transform: Transform = [12.3456, 78.9012, 1.234];
      const screenPos = { x: 123.456, y: 789.012 };

      const result = normalizePointerPosition(screenPos, transform);

      // (123.456 - 12.3456) / 1.234 = 90.04084...
      // (789.012 - 78.9012) / 1.234 = 575.45446...
      expect(result.x).toBeCloseTo(90.04084, 2);
      expect(result.y).toBeCloseTo(575.45446, 2);
    });
  });
});
