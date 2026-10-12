import './style.css';
const root = document.querySelector<HTMLElement>('#app');
if (!root) throw new Error('Missing app root');
root.innerHTML = `<h1>JOBA — админка</h1><p>DEMO · Технический каркас</p><p>RS / KZ / RU / BY</p><p>Управление пользователями, модерацией и монетизацией описано в ТЗ v1 и пока не реализовано.</p><p>Данные пользователей не собираются. Авторизация и платежи не подключены.</p>`;
