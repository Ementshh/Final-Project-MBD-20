# README: Smart Vehicle Dashboard

## 1. Pengenalan Masalah dan Solusi
Menguji sistem akselerasi dan pengereman darurat pada kendaraan fisik secara langsung seringkali berbahaya, membutuhkan biaya tinggi, dan memerlukan persiapan infrastruktur yang besar. Kesalahan sekecil apa pun dalam pengujian sistem rem otomatis dapat berakibat fatal. Oleh karena itu, diperlukan sebuah simulasi yang mudah diimplementasikan, aman, dan berbiaya rendah untuk mengunci, menyalakan, mengemudikan, serta menguji fitur pengereman otomatis sebelum diterapkan pada perangkat keras kendaraan sungguhan.

Sebagai solusi, proyek ini mengembangkan sebuah simulator berbasis mikrokontroler menggunakan Arduino Uno. Sistem ini mmenggunakan sensor RFID sebagai Smart Key, button untuk menyalakan/mematikan mesin, potensiometer sebagai  pedal gas, dan motor servo sebagai repesentasi output kecepatan mesin. Sistem juga dilengkapi dengan fitur Auto Braking yang akan mengambil alih kontrol saat kecepatan melewati batas maksimum yang aman.

## 2. Desain Hardware dan Detail Implementasi
Perangkat keras yang digunakan dalam simulasi ini adalah:
- **Arduino Uno**: Bertindak sebagai otak utama dari simulator.
- **Modul RFID MFRC522**: Berkomunikasi melalui protokol SPI untuk membaca kartu identitas.
- **Potensiometer**: Dihubungkan ke pin Analog (A0) sebagai representasi pedal gas akselerasi.
- **Motor Servo**: Dihubungkan ke pin PWM (Pin 9) sebagai representasi visual dari kecepatan.
- **LCD 1602 dengan modul I2C**: Menampilkan status sistem (LOCKED, ENGINE OFF, DRIVING MODE) dan nilai kecepatan saat berkendara.
- **Push Button (Tombol Tekan)**: Dihubungkan ke pin interrupt (Pin 2 / INT0) untuk menghidupkan dan mematikan mesin.
- **LED Indikator (Hijau, Merah, Oranye) & Active Buzzer**: Digunakan untuk peringatan visual dan audio. Sebuah NOT Gate juga digunakan untuk membalikkan logika LED tertentu terkait kedipan indikator.

## 3. Detail Implementasi Software
Sistem beroperasi berdasarkan *Finite State Machine* (FSM) yang terdiri dari 4 *state* utama:
- **ST_LOCKED (State 0)**: Sistem terkunci. Mikrokontroler terus-menerus polling data dari modul RFID lewat SPI. Jika UID kartu cocok dengan konfigurasi, sistem berpindah ke status tidak terkunci.
- **ST_STOP (State 1)**: Kendaraan terbuka namun mesin mati. Pada tahap ini, pengguna dapat menekan tombol untuk memicu External Interrupt INT0 dan menyalakan mesin.
- **ST_DRIVE (State 2)**: Mode berkendara. Sistem secara kontinu membaca nilai ADC dari letak "setir" potensiometer. Nilai ini diubah menjadi sinyal PWM dengan Timer 1 untuk menggerakkan servo.
- **ST_BRAKE (State 3)**: Auto Braking. Jika nilai gas/kecepatan dari ADC melebihi atau sama dengan 200, mikrokontroler akan override. Nilai kecepatann akan dikurangi 3 terus-menerus dalam loop hingga mencapai dibawah 50, layar LCD akan menampilkan "!! WARNING !! AUTO BRAKING".

## 4. Hasil Pengujian dan Evaluasi Performance
Hasil pengujian:
1.  **Keamanan Akses:** Sistem berhasil menolak kartu acak dan buzzer berbunyi panjang dan menahan state di ST_LOCKED. Kartu yang benar menjalankan sistem pembukaan kunci yang benar dan lanjut ke state ST_STOP.
2.  **Respons Start/Stop Mesin:** Tombol bekerja dengan fitur debounce assembly di dalam Interupsi. Mesin bisa transisi dari ST_STOP ke ST_DRIVE, dan kembali ke ST_STOP saat potensiometer dilepas total, atau kecepatan = 0.
3.  **Tingkat Akselerasi:** Pembacaan ADC potensiometer diterjemahkan menjadi rotasi sudut servo. LCD dan Serial UART mencetak kecepatan secara real-time.
4.  **Uji Auto Braking:** Nilai kecepatan ditingkatkan sampai berada diatas 200, sistem langsung mendeteksi kondisi bahaya, menolak pembacaan ADC baru dari pengguna, dan mengirim perintah pengurangan PWM ke motor servo sampai nilainya di bawah 50 sebelum mengizinkan mode berkendara kembali normal.

## 5. Kesimpulan dan Future Work
**Kesimpulan**
Simulasi "Smart Vehicle Acceleration & Braking System" ini membuktikan bahwa pengujian logika keselamatan kendaraan dan sistem keamanan pintar dapat dimodelkan secara efektif menggunakan komponen murah dan bahasa assembly yang cepat. Menggunakan assembly menjamin respon interupsi instan yang sangat penting, karena waktu yang sangat singkat menentukan diaktifkan atau tidaknya proses auto-braking.

**Future Work**
Sistem dapat dikembangkan dengan menambahkan:
*   Sensor jarak  agar auto-braking aktif bukan hanya dari overspeeding, melainkan saat jarak fisik dengan suatu objek dianggap terlalu dekat melewati batas tertentu.
*   Menggunakan EEPROM untuk menyimpan banyak daftar akses Kunci RFID, sehingga tidak hardcoded di dalam register assembly.