import { fireEvent } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import {
  AdminMaintenancePage,
  type Props,
} from '../../js/design-system/pages/AdminMaintenancePage';

import { renderIsland } from './renderIsland';

describe('AdminMaintenancePage', () => {
  test('each Run sends its event to the LiveView', () => {
    const { pushEvent } = renderIsland<Props>(AdminMaintenancePage, {});

    fireEvent.click(document.getElementById('refresh-adaptors-button')!);
    fireEvent.click(document.getElementById('refresh-icons-button')!);

    expect(pushEvent).toHaveBeenCalledWith('refresh_adaptors', {});
    expect(pushEvent).toHaveBeenCalledWith('refresh_icons', {});
  });
});
