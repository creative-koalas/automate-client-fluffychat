# PsyGo Admin Console

独立静态管理页，支持：

1. 管理员登录
2. 自动刷新 access token
3. 创建用户
4. 查看和搜索用户列表
5. 重置用户密码
6. 更新用户状态

## 文件

1. `index.html`
2. `styles.css`
3. `app.js`

## 使用

如果本地直接调试，建议在仓库根目录启动一个静态服务器，再访问：

```bash
python3 -m http.server 5173
```

打开：

```text
http://localhost:5173/admin-console/
```
