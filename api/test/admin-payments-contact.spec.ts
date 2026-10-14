import { withContact } from '../src/admin/permissions';
import { RoleEnum } from '../src/roles/roles.enum';

/// D-261, amended: in Payments the full email AND the full mobile number reach only a role allowed
/// to see contact details (`users.reveal`). Everyone else keeps the masked ones — and the API
/// removes the full values, so hiding them is never left to the dashboard.
describe('payment contact details by role', () => {
  const row = {
    order_id: 'eatzify_1',
    email: 'asha@example.com',
    email_masked: 'a…@example.com',
    phone: '+919876543210',
    phone_masked: '+919…3210',
  };

  it.each([RoleEnum.super_admin, RoleEnum.admin, RoleEnum.support])(
    'should show role %s the full email and mobile',
    (role) => {
      expect(withContact(role, row)).toMatchObject({
        email: 'asha@example.com',
        phone: '+919876543210',
      });
    },
  );

  it.each([RoleEnum.finance, RoleEnum.content])(
    'should leave role %s only the masked email and mobile',
    (role) => {
      const seen = withContact(role, row);

      expect(seen).not.toHaveProperty('email');
      expect(seen).not.toHaveProperty('phone');
      expect(seen).toMatchObject({
        email_masked: 'a…@example.com',
        phone_masked: '+919…3210',
      });
    },
  );
});
