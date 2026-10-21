import { fireEvent, render } from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';

import { AdminMaintenancePage } from '../../js/design-system/pages/AdminMaintenancePage';

describe('AdminMaintenancePage', () => {
  test('each Run sends its event to the LiveView', () => {
    const pushEvent = vi.fn().mockResolvedValue({});
    render(
      <AdminMaintenancePage
        data-props="{}"
        pushEvent={pushEvent}
        handleEvent={vi.fn()}
        navigate={vi.fn()}
        redirect={vi.fn()}
      />
    );

    fireEvent.click(document.getElementById('refresh-adaptors-button')!);
    fireEvent.click(document.getElementById('refresh-icons-button')!);

    expect(pushEvent).toHaveBeenCalledWith('refresh_adaptors', {});
    expect(pushEvent).toHaveBeenCalledWith('refresh_icons', {});
  });
});
