# Delete account function

This function:

1. verifies the caller's Supabase access token;
2. requires a fresh Apple authorization code for Apple-linked accounts;
3. revokes that authorization with Apple;
4. removes private project files owned by the user's organization; and
5. calls `delete_current_user_account()` to transactionally remove relational
   data and the Supabase Auth user.

Deploy `202607290001_launch_data_integrity_and_account_deletion.sql` before
deploying this function.

For Sign in with Apple revocation, configure these Edge Function secrets:

```text
APPLE_CLIENT_ID=com.constructionestimate.Construction-Estimate
APPLE_TEAM_ID=<Apple developer team ID>
APPLE_KEY_ID=<Sign in with Apple private key ID>
APPLE_PRIVATE_KEY=<contents of the .p8 key>
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are supplied
by the Supabase Edge Function environment.
