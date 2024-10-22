create table if not exists permissions (
    id bigserial primary key,
    code text not null
);

create table if not exists users_permissions (
    user_id bigint not null references users on delete cascade,
    permission_id bigint not null references permissions on delete cascade,
    primary key(user_id, permission_id)
);

INSERT INTO permissions(code)
VALUES 
    ('movies:read'), 
    ('movies:write');
