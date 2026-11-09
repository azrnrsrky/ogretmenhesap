'use strict';
(() => {
  const button = document.querySelector('#sql-help');
  const dialog = document.querySelector('#sql-dialog');
  const text = document.querySelector('#sql-code');
  const message = document.querySelector('#sql-copy-status');
  const copy = document.querySelector('#sql-copy');
  let selected = 'schema';
  let generation = 0;
  async function load(kind) {
    selected = kind;
    const request = ++generation;
    dialog.querySelectorAll('[data-sql]').forEach(tab => {
      tab.classList.toggle('selected', tab.dataset.sql === kind);
      tab.setAttribute('aria-pressed', String(tab.dataset.sql === kind));
    });
    text.value = 'SQL yükleniyor…';
    copy.disabled = true;
    message.textContent = '';
    try {
      const response = await fetch(new URL(`supabase/${kind}.sql`, document.baseURI));
      if (!response.ok) throw new Error('SQL dosyası yüklenemedi. Sayfayı yenileyip tekrar deneyin.');
      const sql = await response.text();
      if (!sql.startsWith('--')) throw new Error('SQL dosyası yerine farklı bir yanıt geldi.');
      if (request !== generation) return;
      text.value = sql;
      copy.disabled = false;
    } catch (error) {
      if (request !== generation) return;
      text.value = '';
      message.textContent = error.message;
    }
  }
  button.onclick = () => { dialog.showModal(); load(selected); };
  document.querySelector('#sql-close').onclick = () => dialog.close();
  dialog.addEventListener('click', event => { if (event.target === dialog) dialog.close(); });
  dialog.querySelectorAll('[data-sql]').forEach(tab => tab.onclick = () => load(tab.dataset.sql));
  copy.onclick = async () => {
    const value = text.value;
    try {
      if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
      await navigator.clipboard.writeText(value);
      message.textContent = 'SQL kodu kopyalandı. Supabase SQL Editor’a yapıştırabilirsiniz.';
    } catch {
      text.focus(); text.select();
      let copied = false;
      try { copied = document.execCommand('copy'); } catch { /* Manual selection remains available. */ }
      message.textContent = copied ? 'SQL kodu kopyalandı.' : 'Kod seçildi. Ctrl+C (Mac: ⌘C) ile kopyalayabilirsiniz.';
    }
  };
})();
