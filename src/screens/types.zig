pub const Screen = enum {
    login,
    register,
};

pub const LoginField = enum {
    username,
    password,
    forgot_password,
    register,
};

pub const RegisterField = enum {
    username,
    password,
    confirm_password,
    create_account,
    back_to_login,
};