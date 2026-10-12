import './style.css';
const root = document.querySelector<HTMLElement>('#app');
if (!root) throw new Error('Missing app root');
root.innerHTML = `<h1>Биржа услуг — админка</h1><p>DEMO · Технический каркас</p><p>RS / KZ / RU / BY</p><p>Управление пользователями, модерацией и монетизацией появится после утверждения ТЗ.</p><p>Данные пользователей не собираются. Авторизация и платежи не подключены.</p>`;
