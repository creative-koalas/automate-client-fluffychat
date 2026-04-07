(function () {
  'use strict';

  const STORAGE_KEY = 'psygo_admin_console_session';
  const REFRESH_AHEAD_MS = 5 * 60 * 1000;
  const DEFAULT_API_BASE = 'http://61.136.165.161:30181/api/v1';
  const DEFAULT_API_SOURCE = 'http://61.136.165.161:30181';
  const UNAUTHORIZED_CODES = new Set([10002, 10003]);

  const state = {
    apiBaseUrl: DEFAULT_API_BASE,
    session: null,
    users: [],
    pagination: {
      page: 1,
      pageSize: 20,
      total: 0,
      hasNextPage: false,
    },
    filters: {
      account: '',
    },
    refreshTimerId: null,
    passwordDialogUser: null,
    selectedUsers: new Set(),
  };

  const elements = {};

  document.addEventListener('DOMContentLoaded', init);

  async function init() {
    bindElements();
    bindEvents();
    initTheme();
    restoreSession();
    await loadEnvConfig();
    render();
    if (state.session) {
      await refreshSessionIfNeeded();
      await loadUsers();
    }
  }

  function initTheme() {
    const savedTheme = localStorage.getItem('psygo_theme');
    if (savedTheme === 'dark') {
      document.documentElement.classList.add('dark');
    } else if (savedTheme === 'light') {
      document.documentElement.classList.add('light');
    }
  }

  function toggleTheme() {
    const isDark = document.documentElement.classList.contains('dark');
    if (isDark) {
      document.documentElement.classList.remove('dark');
      document.documentElement.classList.add('light');
      localStorage.setItem('psygo_theme', 'light');
    } else {
      document.documentElement.classList.remove('light');
      document.documentElement.classList.add('dark');
      localStorage.setItem('psygo_theme', 'dark');
    }
  }

  function bindElements() {
    elements.banner = document.getElementById('banner');
    elements.bannerDetail = document.getElementById('banner-detail');
    elements.apiBaseUrl = document.getElementById('api-base-url');
    elements.sessionCard = document.getElementById('session-card');
    elements.sessionUsername = document.getElementById('session-username');
    elements.sessionRole = document.getElementById('session-role');
    elements.sessionExpiry = document.getElementById('session-expiry');
    elements.headerSessionMeta = document.getElementById('header-session-meta');
    elements.headerSessionUsername = document.getElementById('header-session-username');
    elements.headerSessionRole = document.getElementById('header-session-role');
    elements.forceRefreshBtn = document.getElementById('force-refresh-btn');
    elements.logoutBtn = document.getElementById('logout-btn');
    elements.themeToggle = document.getElementById('theme-toggle');
    elements.loginPanel = document.getElementById('login-panel');
    elements.consolePanel = document.getElementById('console-panel');
    elements.loginForm = document.getElementById('login-form');
    elements.loginUsername = document.getElementById('login-username');
    elements.loginPassword = document.getElementById('login-password');
    elements.loginSubmit = document.getElementById('login-submit');
    elements.createUserForm = document.getElementById('create-user-form');
    elements.bulkCreateForm = document.getElementById('bulk-create-form');
    elements.createAccount = document.getElementById('create-account');
    elements.createPassword = document.getElementById('create-password');
    elements.createConfirmPassword = document.getElementById('create-confirm-password');
    elements.bulkUsersFile = document.getElementById('bulk-users-file');
    elements.bulkFileName = document.getElementById('bulk-file-name');
    elements.bulkFileMeta = document.getElementById('bulk-file-meta');
    elements.searchForm = document.getElementById('search-form');
    elements.searchAccount = document.getElementById('search-account');
    elements.pageSize = document.getElementById('page-size');
    elements.refreshUsersBtn = document.getElementById('refresh-users-btn');
    elements.usersTbody = document.getElementById('users-tbody');
    elements.prevPageBtn = document.getElementById('prev-page-btn');
    elements.nextPageBtn = document.getElementById('next-page-btn');
    elements.paginationSummary = document.getElementById('pagination-summary');
    elements.passwordDialog = document.getElementById('password-dialog');
    elements.passwordDialogForm = document.getElementById('password-dialog-form');
    elements.passwordDialogTitle = document.getElementById('password-dialog-title');
    elements.passwordDialogCancel = document.getElementById('password-dialog-cancel');
    elements.resetPassword = document.getElementById('reset-password');
    elements.resetConfirmPassword = document.getElementById('reset-confirm-password');
    elements.toastDialog = document.getElementById('toast-dialog');
    elements.toastMessage = document.getElementById('toast-message');
    elements.toastDetail = document.getElementById('toast-detail');
    elements.toastClose = document.getElementById('toast-close');
    elements.batchActions = document.getElementById('batch-actions');
    elements.selectedCount = document.getElementById('selected-count');
    elements.selectAll = document.getElementById('select-all');
    elements.batchEnableBtn = document.getElementById('batch-enable-btn');
    elements.batchDisableBtn = document.getElementById('batch-disable-btn');
    elements.batchDeleteBtn = document.getElementById('batch-delete-btn');
  }

  function bindEvents() {
    elements.loginForm.addEventListener('submit', onLoginSubmit);
    elements.logoutBtn.addEventListener('click', onLogoutClick);
    elements.themeToggle.addEventListener('click', toggleTheme);
    elements.forceRefreshBtn.addEventListener('click', async () => {
      await refreshSession(true);
    });
    elements.createUserForm.addEventListener('submit', onCreateUserSubmit);
    elements.bulkCreateForm.addEventListener('submit', onBulkCreateSubmit);
    elements.bulkUsersFile.addEventListener('change', onBulkFileChange);
    elements.searchForm.addEventListener('submit', onSearchSubmit);
    elements.pageSize.addEventListener('change', async () => {
      state.pagination.pageSize = Number(elements.pageSize.value);
      state.pagination.page = 1;
      await loadUsers();
    });
    elements.refreshUsersBtn.addEventListener('click', async () => {
      await loadUsers();
    });
    elements.prevPageBtn.addEventListener('click', async () => {
      if (state.pagination.page <= 1) {
        return;
      }
      state.pagination.page -= 1;
      await loadUsers();
    });
    elements.nextPageBtn.addEventListener('click', async () => {
      if (!state.pagination.hasNextPage) {
        return;
      }
      state.pagination.page += 1;
      await loadUsers();
    });
    elements.passwordDialogCancel.addEventListener('click', closePasswordDialog);
    elements.passwordDialogForm.addEventListener('submit', onPasswordDialogSubmit);
    elements.toastClose.addEventListener('click', closeToastDialog);
    elements.toastDialog.addEventListener('close', closeToastDialog);
    elements.usersTbody.addEventListener('click', onUsersTableClick);
    elements.selectAll.addEventListener('change', onSelectAllChange);
    elements.batchEnableBtn.addEventListener('click', onBatchEnable);
    elements.batchDisableBtn.addEventListener('click', onBatchDisable);
    elements.batchDeleteBtn.addEventListener('click', onBatchDelete);
    document.querySelectorAll('[data-toggle-password]').forEach((button) => {
      button.addEventListener('click', onTogglePasswordClick);
    });
  }

  async function loadEnvConfig(showToast) {
    const candidates = ['/env.json', '../env.json', './env.json'];
    let loaded = false;

    for (const url of candidates) {
      try {
        const response = await fetch(url, { cache: 'no-store' });
        if (!response.ok) {
          continue;
        }
        const config = await response.json();
        if (!config || !config.API_BASE_URL) {
          continue;
        }
        state.apiBaseUrl = normalizeApiBaseUrl(config.API_BASE_URL);
        loaded = true;
        break;
      } catch (error) {
        void error;
      }
    }

    if (!loaded) {
      state.apiBaseUrl = DEFAULT_API_BASE;
    }
    elements.apiBaseUrl.value = state.apiBaseUrl;
    if (showToast) {
      showBanner(
        loaded ? `已从 env.json 读取 ${state.apiBaseUrl}` : `未读到 env.json，继续使用 ${state.apiBaseUrl}`,
        loaded ? 'success' : 'error'
      );
    }
  }

  function restoreSession() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) {
        return;
      }
      const session = JSON.parse(raw);
      if (!session || !session.accessToken) {
        return;
      }
      state.session = session;
      state.apiBaseUrl = normalizeApiBaseUrl(session.apiBaseUrl || state.apiBaseUrl);
      scheduleTokenRefresh();
    } catch (error) {
      console.error('Failed to restore session', error);
    }
  }

  function saveSession(session) {
    state.session = session;
    localStorage.setItem(STORAGE_KEY, JSON.stringify(session));
    scheduleTokenRefresh();
    render();
  }

  function clearSession() {
    state.session = null;
    state.users = [];
    state.pagination.page = 1;
    state.pagination.total = 0;
    state.pagination.hasNextPage = false;
    state.selectedUsers.clear();
    localStorage.removeItem(STORAGE_KEY);
    if (state.refreshTimerId) {
      window.clearTimeout(state.refreshTimerId);
      state.refreshTimerId = null;
    }
    elements.loginUsername.value = '';
    elements.loginPassword.value = '';
    render();
  }

  function scheduleTokenRefresh() {
    if (state.refreshTimerId) {
      window.clearTimeout(state.refreshTimerId);
      state.refreshTimerId = null;
    }
    if (!state.session || !state.session.expiresAt) {
      return;
    }

    const delay = Math.max(state.session.expiresAt - Date.now() - REFRESH_AHEAD_MS, 5_000);
    state.refreshTimerId = window.setTimeout(() => {
      refreshSession(true).catch((error) => {
        console.error('Auto refresh failed', error);
      });
    }, delay);
  }

  function normalizeApiBaseUrl(input) {
    const value = String(input || '').trim().replace(/\/+$/, '');
    if (!value) {
      return DEFAULT_API_BASE;
    }
    if (value.endsWith('/api/v1')) {
      return value;
    }
    if (value.endsWith('/api')) {
      return value + '/v1';
    }
    return value + '/api/v1';
  }

  function showBanner(message, type, detail) {
    // Use toast dialog instead of inline banner
    elements.toastMessage.textContent = message;
    elements.toastMessage.classList.remove('error', 'success');
    if (type) {
      elements.toastMessage.classList.add(type);
    }
    if (detail) {
      elements.toastDetail.textContent = detail;
      elements.toastDetail.classList.remove('hidden');
    } else {
      elements.toastDetail.classList.add('hidden');
      elements.toastDetail.textContent = '';
    }
    elements.toastDialog.showModal();
  }

  function hideBanner() {
    if (elements.toastDialog.open) {
      elements.toastDialog.close();
    }
  }

  function closeToastDialog() {
    elements.toastDialog.close();
  }

  function render() {
    const isLoggedIn = Boolean(state.session && state.session.accessToken);
    elements.loginPanel.classList.toggle('hidden', isLoggedIn);
    elements.consolePanel.classList.toggle('hidden', !isLoggedIn);
    elements.sessionCard.classList.toggle('hidden', !isLoggedIn);
    elements.headerSessionMeta.classList.toggle('hidden', !isLoggedIn);
    elements.apiBaseUrl.value = state.apiBaseUrl;
    elements.pageSize.value = String(state.pagination.pageSize);
    elements.searchAccount.value = state.filters.account;

    if (!isLoggedIn) {
      elements.sessionUsername.textContent = '-';
      elements.sessionRole.textContent = '-';
      elements.sessionExpiry.textContent = '-';
      elements.headerSessionUsername.textContent = '-';
      elements.headerSessionRole.textContent = '-';
      renderUsers([]);
      return;
    }

    elements.sessionUsername.textContent = state.session.username || '-';
    elements.sessionRole.textContent = state.session.role || '-';
    elements.sessionExpiry.textContent = formatDateTime(state.session.expiresAt);
    elements.headerSessionUsername.textContent = state.session.username || '-';
    elements.headerSessionRole.textContent = state.session.role || '-';
    renderUsers(state.users);
  }

  function renderUsers(users) {
    if (!Array.isArray(users) || users.length === 0) {
      elements.usersTbody.innerHTML =
        '<tr><td colspan="6" class="empty-cell">当前没有可展示的用户数据。</td></tr>';
    } else {
      elements.usersTbody.innerHTML = users
        .map((user) => {
          const currentStatus = user.status || 'active';
          const isSelected = state.selectedUsers.has(user.id);
          const createdAt = formatDateTime(user.created_at);
          const updatedAt = formatDateTime(user.updated_at);
          return `
            <tr data-user-id="${escapeHtml(user.id)}">
              <td class="checkbox-col">
                <input type="checkbox" class="user-checkbox" data-user-id="${escapeHtml(user.id)}" ${isSelected ? 'checked' : ''} />
              </td>
              <td>${escapeHtml(user.account || '-')}</td>
              <td>
                <select class="status-select" data-user-id="${escapeHtml(user.id)}">
                  <option value="active" ${currentStatus === 'active' ? 'selected' : ''}>启用</option>
                  <option value="inactive" ${currentStatus === 'inactive' ? 'selected' : ''}>禁用</option>
                </select>
              </td>
              <td>${createdAt}</td>
              <td>${updatedAt}</td>
              <td>
                <button class="ghost-button" type="button" data-action="reset-password" data-user-id="${escapeHtml(user.id)}" data-account="${escapeHtml(user.account || '')}">
                  修改密码
                </button>
              </td>
            </tr>
          `;
        })
        .join('');
    }

    // Update select all checkbox
    const checkboxes = elements.usersTbody.querySelectorAll('.user-checkbox');
    const allSelected = checkboxes.length > 0 && Array.from(checkboxes).every(cb => cb.checked);
    elements.selectAll.checked = allSelected;
    elements.selectAll.indeterminate = !allSelected && Array.from(checkboxes).some(cb => cb.checked);

    // Update batch actions visibility and count
    updateBatchActions();

    const start = state.pagination.total === 0 ? 0 : (state.pagination.page - 1) * state.pagination.pageSize + 1;
    const end = Math.min(state.pagination.page * state.pagination.pageSize, state.pagination.total);
    elements.paginationSummary.textContent =
      `第 ${state.pagination.page} 页 · ${start}-${end} / ${state.pagination.total}`;
    elements.prevPageBtn.disabled = state.pagination.page <= 1;
    elements.nextPageBtn.disabled = !state.pagination.hasNextPage;
  }

  function updateBatchActions() {
    const count = state.selectedUsers.size;
    if (count === 0) {
      elements.batchActions.classList.add('hidden');
    } else {
      elements.batchActions.classList.remove('hidden');
      elements.selectedCount.textContent = `已选择 ${count} 项`;
    }
  }

  async function updateUserStatus(userId, status) {
    const statusText = status === 'active' ? '启用' : '禁用';
    try {
      await request(`/users/${encodeURIComponent(userId)}/status`, {
        method: 'PUT',
        body: { status },
      });
      showBanner(`用户${statusText}成功。`, 'success');
      await loadUsers();
    } catch (error) {
      showBanner(error.message || `${statusText}失败。`, 'error');
      await loadUsers(); // Reset select to current state
    }
  }

  function buildStatusOptions(currentStatus) {
    const statuses = ['active', 'inactive', 'banned', 'deleted'];
    return statuses
      .map((status) => {
        const selected = status === currentStatus ? 'selected' : '';
        return `<option value="${status}" ${selected}>${status}</option>`;
      })
      .join('');
  }

  async function onLoginSubmit(event) {
    event.preventDefault();
    hideBanner();
    setLoading(elements.loginSubmit, true, '登录中...');

    try {
      state.apiBaseUrl = normalizeApiBaseUrl(elements.apiBaseUrl.value);
      const username = elements.loginUsername.value.trim();
      const password = elements.loginPassword.value;
      const result = await loginWithBestStrategy(username, password);
      const expiresIn = Number(result.expires_in || 7200);

      saveSession({
        apiBaseUrl: state.apiBaseUrl,
        accessToken: result.access_token,
        refreshToken: result.refresh_token || null,
        expiresAt: Date.now() + expiresIn * 1000,
        username: result.username || result.account || username,
        role: result.role || 'admin',
      });
      elements.loginPassword.value = '';
      if (result.refresh_token) {
        showBanner('登录成功，已启用自动刷新 token。', 'success');
      } else {
        showBanner('登录成功，但管理员接口未返回 refresh token。需要时可手动更新 token，或到期后重新登录。', 'error');
      }
      await loadUsers();
    } catch (error) {
      showBanner(error.message || '登录失败。', 'error');
    } finally {
      setLoading(elements.loginSubmit, false, '登录');
    }
  }

  async function loginWithBestStrategy(username, password) {
    try {
      const result = await request('/auth/login', {
        method: 'POST',
        body: {
          account: username,
          password,
        },
        auth: false,
      });
      if (result.role && result.role !== 'admin') {
        throw new Error('当前账号不是管理员。');
      }
      return result;
    } catch (primaryError) {
      const fallbackResult = await request('/auth/admin/login', {
        method: 'POST',
        body: {
          username,
          password,
        },
        auth: false,
      });
      return fallbackResult;
    }
  }

  async function onLogoutClick() {
    if (!state.session) {
      clearSession();
      return;
    }

    try {
      if (state.session.refreshToken) {
        await request('/auth/logout', {
          method: 'POST',
          body: { refresh_token: state.session.refreshToken },
        });
      }
    } catch (error) {
      console.warn('Logout request failed', error);
    } finally {
      clearSession();
      state.users = [];
      showBanner('已退出登录。', 'success');
    }
  }

  async function onCreateUserSubmit(event) {
    event.preventDefault();
    hideBanner();
    const submitButton = event.submitter;
    setLoading(submitButton, true, '创建中...');

    try {
      validateCreateUserInput(
        elements.createAccount.value.trim(),
        elements.createPassword.value,
        elements.createConfirmPassword.value
      );
      await request('/admin/users', {
        method: 'POST',
        body: {
          account: elements.createAccount.value.trim(),
          password: elements.createPassword.value,
          confirm_password: elements.createConfirmPassword.value,
        },
      });
      elements.createUserForm.reset();
      showBanner('用户创建成功。', 'success');
      await loadUsers();
    } catch (error) {
      showBanner(error.message || '创建用户失败。', 'error');
    } finally {
      setLoading(submitButton, false, '创建用户');
    }
  }

  async function onBulkCreateSubmit(event) {
    event.preventDefault();
    hideBanner();
    const submitButton = event.submitter;
    setLoading(submitButton, true, '上传中...');

    try {
      const file = elements.bulkUsersFile.files && elements.bulkUsersFile.files[0];
      if (!file) {
        throw new Error('请选择要导入的 Excel 文件。');
      }
      if (!/\.(xlsx|xls)$/i.test(file.name)) {
        throw new Error('文件格式不正确，只支持 .xlsx 或 .xls。');
      }

      const result = await uploadFileRequest('/admin/users/import', file);
      await loadUsers();

      const createdCount = Number(result.created_count || 0);
      const updatedCount = Number(result.updated_count || 0);
      const failedCount = Number(result.failed_count || 0);
      const warnings = Array.isArray(result.warnings) ? result.warnings : [];
      const errorGroups = Array.isArray(result.error_groups) ? result.error_groups : [];

      elements.bulkCreateForm.reset();
      resetBulkFilePicker();

      // Build detail message
      const detailLines = [];

      // Warnings section
      warnings.forEach((warning) => {
        const accounts = Array.isArray(warning.accounts) ? warning.accounts.join('、') : '';
        detailLines.push(`⚠️ ${translateErrorType(warning.type) || warning.message || '未知警告'}${accounts ? `\n${accounts}` : ''}`);
      });

      // Errors section
      errorGroups.forEach((group) => {
        const accounts = Array.isArray(group.accounts) ? group.accounts.join('、') : '';
        const errorType = translateErrorType(group.type);
        const message = group.message || (errorType ? errorType : '未知错误');
        detailLines.push(`❌ ${message}${accounts ? `\n${accounts}` : ''}`);
      });

      const hasFailures = failedCount > 0 || detailLines.length > 0;
      let summaryMessage = `导入完成：新建 ${createdCount} 条，更新 ${updatedCount} 条，失败 ${failedCount} 条。`;

      if (result.failure_export_token && failedCount > 0) {
        summaryMessage += '\n\n点击确定下载失败记录（Excel 格式）。';
      }

      showBanner(
        summaryMessage,
        hasFailures ? 'error' : 'success',
        detailLines.length > 0 ? detailLines.join('\n\n') : ''
      );

      // Auto download failures if any
      if (result.failure_export_token && failedCount > 0) {
        setTimeout(() => {
          downloadFailures(result.failure_export_token);
        }, 1000);
      }
    } catch (error) {
      showBanner(error.message || '批量创建失败。', 'error');
    } finally {
      setLoading(submitButton, false, '上传导入');
    }
  }

  function translateErrorType(type) {
    const typeMap = {
      'account_invalid': '用户名格式错误',
      'account_too_short': '用户名长度不足（需 6-32 位）',
      'account_too_long': '用户名长度超出限制（需 6-32 位）',
      'account_invalid_chars': '用户名包含非法字符',
      'account_duplicate_in_db': '用户名已存在',
      'password_too_short': '密码长度不足（需 6-32 位）',
      'password_too_long': '密码长度超出限制（需 6-32 位）',
      'password_same_as_account': '密码与用户名相同',
      'password_same_as_username': '密码与用户名相同',
      'password_weak': '密码强度不足',
      'duplicate_in_file': '同一文件内用户名重复',
      'invalid_row': '无效的行数据',
    };
    return typeMap[type] || type;
  }

  function downloadFailures(token) {
    const url = state.apiBaseUrl + `/admin/users/import/failures/${encodeURIComponent(token)}`;
    const a = document.createElement('a');
    a.href = url;
    a.download = 'failures.xlsx';
    if (state.session && state.session.accessToken) {
      a.headers = {
        Authorization: `Bearer ${state.session.accessToken}`,
      };
    }
    // Use fetch to add auth header
    fetch(url, {
      headers: {
        Authorization: `Bearer ${state.session.accessToken}`,
      },
    })
      .then((response) => response.blob())
      .then((blob) => {
        const downloadUrl = window.URL.createObjectURL(blob);
        a.href = downloadUrl;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        window.URL.revokeObjectURL(downloadUrl);
      })
      .catch((error) => {
        console.error('Download failed:', error);
      });
  }

  function onBulkFileChange() {
    const file = elements.bulkUsersFile.files && elements.bulkUsersFile.files[0];
    if (!file) {
      resetBulkFilePicker();
      return;
    }
    elements.bulkFileName.textContent = file.name;
    elements.bulkFileMeta.textContent = `${formatFileSize(file.size)} · 点击重新选择`;
  }

  async function onSearchSubmit(event) {
    event.preventDefault();
    state.filters.account = elements.searchAccount.value.trim();
    state.pagination.page = 1;
    await loadUsers();
  }

  async function onUsersTableClick(event) {
    const target = event.target;

    // Handle checkbox clicks
    if (target.classList.contains('user-checkbox')) {
      const userId = target.getAttribute('data-user-id');
      if (target.checked) {
        state.selectedUsers.add(userId);
      } else {
        state.selectedUsers.delete(userId);
      }
      updateBatchActions();
      return;
    }

    // Handle status select changes
    if (target.classList.contains('status-select')) {
      const userId = target.getAttribute('data-user-id');
      const newStatus = target.value;
      await updateUserStatus(userId, newStatus);
      return;
    }

    const action = target.getAttribute('data-action');
    if (!action) {
      return;
    }

    const userId = target.getAttribute('data-user-id');
    if (!userId) {
      return;
    }

    if (action === 'reset-password') {
      const account = target.getAttribute('data-account') || '';
      openPasswordDialog({ id: userId, account });
    }
  }

  function onSelectAllChange() {
    const checkboxes = elements.usersTbody.querySelectorAll('.user-checkbox');
    if (elements.selectAll.checked) {
      checkboxes.forEach(cb => {
        cb.checked = true;
        state.selectedUsers.add(cb.getAttribute('data-user-id'));
      });
    } else {
      checkboxes.forEach(cb => {
        cb.checked = false;
        state.selectedUsers.delete(cb.getAttribute('data-user-id'));
      });
    }
    updateBatchActions();
  }

  async function onBatchEnable() {
    await batchUpdateStatus('active');
  }

  async function onBatchDisable() {
    await batchUpdateStatus('inactive');
  }

  async function batchUpdateStatus(status) {
    const userIds = Array.from(state.selectedUsers);
    if (userIds.length === 0) {
      showBanner('请先选择用户。', 'error');
      return;
    }

    const statusText = status === 'active' ? '启用' : '禁用';
    setLoading(elements.batchEnableBtn, true, '处理中...');

    try {
      let successCount = 0;
      let failCount = 0;
      const failedAccounts = [];

      for (const userId of userIds) {
        try {
          await request(`/users/${encodeURIComponent(userId)}/status`, {
            method: 'PUT',
            body: { status },
          });
          successCount++;
        } catch (error) {
          failCount++;
          const user = state.users.find(u => u.id === userId);
          if (user) {
            failedAccounts.push(user.account || userId);
          }
        }
      }

      state.selectedUsers.clear();
      await loadUsers();

      if (failCount === 0) {
        showBanner(`${statusText}成功：${successCount} 个用户。`, 'success');
      } else {
        showBanner(`${statusText}完成：成功 ${successCount} 个，失败 ${failCount} 个。`, 'error', failedAccounts.join('、'));
      }
    } finally {
      setLoading(elements.batchEnableBtn, false, '启用');
      setLoading(elements.batchDisableBtn, false, '禁用');
    }
  }

  async function onBatchDelete() {
    const userIds = Array.from(state.selectedUsers);
    if (userIds.length === 0) {
      showBanner('请先选择用户。', 'error');
      return;
    }

    if (!confirm(`确定要删除选中的 ${userIds.length} 个用户吗？此操作不可撤销。`)) {
      return;
    }

    setLoading(elements.batchDeleteBtn, true, '删除中...');

    try {
      await request('/users/batch', {
        method: 'DELETE',
        body: { user_ids: userIds },
      });

      state.selectedUsers.clear();
      await loadUsers();
      showBanner(`删除成功：${userIds.length} 个用户。`, 'success');
    } catch (error) {
      showBanner(error.message || '删除失败。', 'error');
    } finally {
      setLoading(elements.batchDeleteBtn, false, '删除');
    }
  }

  function openPasswordDialog(user) {
    state.passwordDialogUser = user;
    elements.passwordDialogTitle.textContent = `重置密码 · ${user.account || user.id}`;
    elements.resetPassword.value = '';
    elements.resetConfirmPassword.value = '';
    elements.passwordDialog.showModal();
  }

  function closePasswordDialog() {
    state.passwordDialogUser = null;
    elements.passwordDialog.close();
  }

  async function onPasswordDialogSubmit(event) {
    event.preventDefault();
    if (!state.passwordDialogUser) {
      return;
    }

    const submitButton = event.submitter;
    setLoading(submitButton, true, '保存中...');
    try {
      validatePasswordInput(
        state.passwordDialogUser.account || '',
        elements.resetPassword.value,
        elements.resetConfirmPassword.value
      );
      await request(`/users/${encodeURIComponent(state.passwordDialogUser.id)}/password`, {
        method: 'PUT',
        body: {
          password: elements.resetPassword.value,
          confirm_password: elements.resetConfirmPassword.value,
        },
      });
      closePasswordDialog();
      showBanner('密码已更新。', 'success');
    } catch (error) {
      showBanner(error.message || '密码更新失败。', 'error');
    } finally {
      setLoading(submitButton, false, '保存');
    }
  }

  async function loadUsers() {
    if (!state.session) {
      return;
    }

    // Clear selected users when reloading
    state.selectedUsers.clear();

    try {
      hideBanner();
      const params = new URLSearchParams({
        page: String(state.pagination.page),
        page_size: String(state.pagination.pageSize),
      });
      if (state.filters.account) {
        params.set('account', state.filters.account);
      }

      const result = await request(`/users?${params.toString()}`);
      const fetchedUsers = Array.isArray(result.users) ? result.users : [];
      const filterTerm = state.filters.account.trim().toLowerCase();
      state.users = filterTerm
        ? fetchedUsers.filter((user) =>
            String(user.account || '').toLowerCase().includes(filterTerm)
          )
        : fetchedUsers;
      state.pagination.total = Number(result.total || result.count || 0);
      state.pagination.hasNextPage = Boolean(result.has_next_page);
      render();
    } catch (error) {
      showBanner(error.message || '加载用户列表失败。', 'error');
      state.users = [];
      render();
    }
  }

  async function refreshSessionIfNeeded() {
    if (!state.session) {
      return false;
    }
    if (!state.session.expiresAt || state.session.expiresAt - Date.now() > REFRESH_AHEAD_MS) {
      return true;
    }
    return refreshSession(false);
  }

  async function refreshSession(showToast) {
    if (!state.session || !state.session.refreshToken) {
      if (showToast) {
        showBanner('当前会话没有 refresh token，无法自动刷新。可以点“手动更新 Token”直接覆盖。', 'error');
      }
      return false;
    }

    try {
      const result = await rawRequest('/auth/refresh-token', {
        method: 'POST',
        auth: false,
        body: {
          refresh_token: state.session.refreshToken,
        },
      });

      const expiresIn = Number(result.expires_in || 7200);
      saveSession({
        ...state.session,
        accessToken: result.access_token,
        refreshToken: result.refresh_token || state.session.refreshToken,
        expiresAt: Date.now() + expiresIn * 1000,
      });
      if (showToast) {
        showBanner('Token 已刷新。', 'success');
      }
      return true;
    } catch (error) {
      clearSession();
      showBanner(error.message || 'Token 刷新失败，请重新登录。', 'error');
      return false;
    }
  }

  async function request(path, options) {
    const authorized = options && options.auth !== false;
    if (authorized) {
      const ok = await refreshSessionIfNeeded();
      if (!ok) {
        throw new Error('登录已失效，请重新登录。');
      }
    }

    try {
      return await rawRequest(path, options);
    } catch (error) {
      const shouldRetry =
        authorized &&
        (error.status === 401 || UNAUTHORIZED_CODES.has(Number(error.code)));
      if (!shouldRetry) {
        throw error;
      }

      const refreshed = await refreshSession(false);
      if (!refreshed) {
        throw new Error('登录已失效，请重新登录。');
      }
      return rawRequest(path, options);
    }
  }

  async function rawRequest(path, options) {
    const requestOptions = options || {};
    const headers = {
      Accept: 'application/json',
    };
    const hasBody = requestOptions.body !== undefined;
    let body;

    if (requestOptions.auth !== false && state.session && state.session.accessToken) {
      headers.Authorization = `Bearer ${state.session.accessToken}`;
    }

    if (hasBody) {
      headers['Content-Type'] = 'application/json';
      body = JSON.stringify(requestOptions.body);
    }

    let response;
    try {
      response = await fetch(state.apiBaseUrl + path, {
        method: requestOptions.method || 'GET',
        headers,
        body,
      });
    } catch (error) {
      const networkError = new Error(buildNetworkErrorMessage(path, error));
      networkError.status = 0;
      networkError.code = 'NETWORK_ERROR';
      throw networkError;
    }

    let payload = null;
    try {
      payload = await response.json();
    } catch (error) {
      void error;
    }

    if (!response.ok) {
      const error = new Error(formatBackendMessage((payload && payload.message) || `HTTP ${response.status}`));
      error.status = response.status;
      error.code = payload && payload.code;
      throw error;
    }

    if (!payload) {
      return {};
    }

    if (payload.code !== 0) {
      const error = new Error(formatBackendMessage(payload.message || '请求失败'));
      error.status = response.status;
      error.code = payload.code;
      throw error;
    }

    return payload.data || {};
  }

  async function uploadFileRequest(path, file) {
    if (!state.session || !state.session.accessToken) {
      throw new Error('登录已失效，请重新登录。');
    }

    const ok = await refreshSessionIfNeeded();
    if (!ok) {
      throw new Error('登录已失效，请重新登录。');
    }

    const formData = new FormData();
    formData.append('file', file);

    let response;
    try {
      response = await fetch(state.apiBaseUrl + path, {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          Authorization: `Bearer ${state.session.accessToken}`,
        },
        body: formData,
      });
    } catch (error) {
      const networkError = new Error(buildNetworkErrorMessage(path, error));
      networkError.status = 0;
      networkError.code = 'NETWORK_ERROR';
      throw networkError;
    }

    let payload = null;
    try {
      payload = await response.json();
    } catch (error) {
      void error;
    }

    if (!response.ok) {
      const requestError = new Error(formatBackendMessage((payload && payload.message) || `HTTP ${response.status}`));
      requestError.status = response.status;
      requestError.code = payload && payload.code;
      throw requestError;
    }

    if (!payload || payload.code !== 0) {
      const requestError = new Error(formatBackendMessage((payload && payload.message) || '导入失败'));
      requestError.status = response.status;
      requestError.code = payload && payload.code;
      throw requestError;
    }

    return payload.data || {};
  }

  function setLoading(button, loading, label) {
    if (!button) {
      return;
    }
    if (!button.dataset.originalLabel) {
      button.dataset.originalLabel = button.textContent;
    }
    button.disabled = loading;
    button.textContent = loading ? label : button.dataset.originalLabel;
  }

  function onTogglePasswordClick(event) {
    const button = event.currentTarget;
    const inputId = button.getAttribute('data-toggle-password');
    const input = document.getElementById(inputId);
    if (!input) {
      return;
    }
    const nextType = input.type === 'password' ? 'text' : 'password';
    input.type = nextType;
    const visible = nextType === 'text';
    button.classList.toggle('is-visible', visible);
    button.setAttribute('aria-label', visible ? '隐藏密码' : '显示密码');
    button.setAttribute('title', visible ? '隐藏密码' : '显示密码');
  }

  function validateCreateUserInput(account, password, confirmPassword) {
    if (!/^[A-Za-z0-9_-]{6,32}$/.test(account)) {
      throw new Error('用户名需为 6-32 位，且只能包含字母、数字、下划线或连字符。');
    }
    validatePasswordInput(account, password, confirmPassword);
  }

  function validatePasswordInput(account, password, confirmPassword) {
    if (password !== confirmPassword) {
      throw new Error('两次输入的密码不一致。');
    }
    if (password.length < 6 || password.length > 32) {
      throw new Error('密码长度需为 6-32 位。');
    }
    if (password === account) {
      throw new Error('密码不能与用户名相同。');
    }
    const hasUpper = /[A-Z]/.test(password);
    const hasLower = /[a-z]/.test(password);
    const hasDigit = /\d/.test(password);
    const kinds = [hasUpper, hasLower, hasDigit].filter(Boolean).length;
    if (kinds < 2 || /^\d+$/.test(password) || /^[A-Za-z]+$/.test(password)) {
      throw new Error('密码需至少包含大写字母、小写字母、数字中的 2 种，且不能为纯字母或纯数字。');
    }
  }

  function formatBackendMessage(message) {
    const text = String(message || '').trim();
    if (!text) {
      return '请求失败。';
    }
    // 登录错误
    if (text.toLowerCase().includes('invalid username') ||
        text.toLowerCase().includes('invalid password') ||
        text.toLowerCase().includes('incorrect password') ||
        text.toLowerCase().includes('account or password')) {
      return '用户名或密码错误。';
    }
    if (text.toLowerCase().includes('account is locked') || text.toLowerCase().includes('locked')) {
      return '账号已被锁定，请 15 分钟后再试。';
    }
    if (text.toLowerCase().includes('user not found') || text.toLowerCase().includes('account not found')) {
      return '用户不存在。';
    }
    if (text.toLowerCase().includes('login') && text.toLowerCase().includes('fail')) {
      return '登录失败，请检查用户名和密码。';
    }
    if (text.includes("CreateUserRequest.Account") && text.includes("'min'")) {
      return '用户名太短。用户名需至少 6 位，只能包含字母、数字、下划线或连字符。';
    }
    if (text.includes("CreateUserRequest.Account") && text.includes("'max'")) {
      return '用户名太长。用户名最长 32 位。';
    }
    if (text.includes("CreateUserRequest.Account") && text.includes("'alphanumunicode'")) {
      return '用户名格式不合法。只能包含字母、数字、下划线或连字符。';
    }
    if (text.includes("CreateUserRequest.Account") && text.includes("'required'")) {
      return '用户名不能为空。';
    }
    if (text.includes('password_same_as_account')) {
      return '密码不能与用户名相同。';
    }
    if (text.includes("Password") && text.includes("'min'")) {
      return '密码太短。密码至少需要 6 位。';
    }
    if (text.includes("Password") && text.includes("'max'")) {
      return '密码太长。密码最长 32 位。';
    }
    if (text.includes('confirm_password')) {
      return '确认密码校验失败，请检查两次输入是否一致。';
    }
    return text;
  }

  function buildNetworkErrorMessage(path, error) {
    const reason = error && error.message ? String(error.message) : '网络请求失败';
    return `请求失败，未能连接到后端接口。
可能原因：
1. 当前页面地址未被后端 CORS 放行
2. 后端服务不可达
3. API 地址配置不正确

请求地址：${state.apiBaseUrl + path}
底层错误：${reason}`;
  }

  function formatDateTime(value) {
    if (!value) {
      return '-';
    }
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return '-';
    }
    return new Intl.DateTimeFormat('zh-CN', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false,
    }).format(date);
  }

  function formatFileSize(bytes) {
    if (!Number.isFinite(bytes) || bytes <= 0) {
      return '未知大小';
    }
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`;
    }
    return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  }

  function resetBulkFilePicker() {
    elements.bulkFileName.textContent = '选择 Excel 文件';
    elements.bulkFileMeta.textContent = '支持 .xlsx / .xls';
  }

  function escapeHtml(value) {
    return String(value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function cssEscape(value) {
    if (window.CSS && typeof window.CSS.escape === 'function') {
      return window.CSS.escape(value);
    }
    return String(value).replace(/"/g, '\\"');
  }
})();
