const AdminAuth = (() => {
  const client = supabase.createClient(ADMIN_SUPABASE_CONFIG.url, ADMIN_SUPABASE_CONFIG.publishableKey);

  const getAdminUser = async () => {
    const { data: sessionData } = await client.auth.getSession();
    if (!sessionData.session) return null;

    const { data, error } = await client.auth.getUser();
    if (error || !data.user || data.user.app_metadata?.role !== 'admin') return null;
    return data.user;
  };

  const requireAdmin = async () => {
    const user = await getAdminUser();
    if (!user) {
      window.location.replace('index.html');
      return null;
    }
    return user;
  };

  const signIn = async (email, password) => {
    const { error } = await client.auth.signInWithPassword({ email, password });
    if (error) throw error;
    const user = await getAdminUser();
    if (!user) {
      await client.auth.signOut();
      throw new Error('La cuenta no tiene permisos de administración.');
    }
    return user;
  };

  const signOut = () => client.auth.signOut();
  return { client, getAdminUser, requireAdmin, signIn, signOut };
})();

document.addEventListener('DOMContentLoaded', async () => {
  const form = document.querySelector('#login-form');
  if (!form) return;

  const message = document.querySelector('#auth-message');
  const button = document.querySelector('#login-button');
  try {
    if (await AdminAuth.getAdminUser()) window.location.replace('admin.html');
  } catch (_) {
    message.textContent = 'No fue posible comprobar la sesión. Intentá nuevamente.';
  }

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    message.textContent = '';
    button.disabled = true;
    try {
      await AdminAuth.signIn(form.email.value.trim(), form.password.value);
      window.location.replace('admin.html');
    } catch (error) {
      message.textContent = error.message === 'La cuenta no tiene permisos de administración.'
        ? error.message
        : 'No fue posible iniciar sesión. Verificá tus credenciales.';
    } finally {
      button.disabled = false;
    }
  });
});
