# PASR_PRERELEASE Log Reference

Log path:
`/home/agus/.mt5/drive_c/Program Files/MetaTrader 5/MQL5/Experts/PASR_PRERELEASE.log`

Encoding: UTF-16LE.

Key finding: compile produced 5 errors, all on `PASR_PRERELEASE.mq5` line 251.

Error cluster:
- `'CJournalManager *journal = services->Journal())` atau ekspresi metode `Journal()` dari `CServiceLocator *services`
- Case ini sering terjadi saat:
  - include cascade berubah dan `CServiceLocator::Journal()` tidak lagi terekspos
  - method yang benar bernama `GetJournal()` atau aksesnya lewat property bernama lain
  - header `JournalManager` belum di-include di scope yang benar
- Repair priority:
  1. Pastikan `PASR_PRERELEASE.mq5` sudah termasuk include yang mengexpose `CJournalManager` dan aksesor di `CServiceLocator`
  2. Jika method tidak ada, ganti `services->Journal()` dengan nama aksesor yang didefinisikan oleh versi include yang aktif saat ini

Related:
- Include root: `PASR/Core/PASR.mqh`
- Include journal infra: `PASR/Infra/JournalManager.mqh`
- File EA: `/home/agus/.mt5/drive_c/Program Files/MetaTrader 5/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/Experts/PASR_PRERELEASE.mq5`
