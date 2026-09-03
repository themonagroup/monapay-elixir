# Changelog

## 0.4.0

- Thêm `PaymentProfile`, `Checkouts`, xem lại/xoay secret hồ sơ và API key.
- Tự sinh `Idempotency-Key` cho tạo/huỷ checkout và cho phép truyền key riêng.

## 0.3.0

- Client credentials mặc định, token có hạn và factory `MonaPay.from_env/1`.
- Thêm sandbox transactions, email configs, email logs và email suppressions.

## 0.1.0

- Bản đầu tiên: full client surface, transaction Stream và webhook verification stdlib-only.
