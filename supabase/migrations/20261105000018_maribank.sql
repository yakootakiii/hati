-- Hati — MariBank as a payment method (DECISIONS D-62).
--
-- MariBank (formerly SeaBank PH) is a digital bank people pay into by account
-- number or QR Ph, so it joins the list next to the e-wallets.

alter table public.payment_methods
  drop constraint payment_methods_type_check,
  add constraint payment_methods_type_check check (type in (
    'gcash', 'maya', 'gotyme', 'shopeepay', 'grabpay', 'coinsph',
    'palawanpay', 'maribank', 'bank', 'other'
  ));

alter table public.payments
  drop constraint payments_method_check,
  add constraint payments_method_check check (method in (
    'gcash', 'maya', 'gotyme', 'shopeepay', 'grabpay', 'coinsph',
    'palawanpay', 'maribank', 'bank', 'cash', 'other'
  ));
