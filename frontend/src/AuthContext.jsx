import React, { createContext, useContext, useState, useCallback } from "react";
import { api } from "./api";

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(() => {
    const stored = localStorage.getItem("stocksense_user");
    return stored ? JSON.parse(stored) : null;
  });

  const login = useCallback(async (email, password) => {
    const data = await api.login({ email, password });
    localStorage.setItem("stocksense_token", data.access_token);
    const userObj = { name: data.user_name, role: data.role, email };
    localStorage.setItem("stocksense_user", JSON.stringify(userObj));
    setUser(userObj);
    return userObj;
  }, []);

  const signup = useCallback(async (name, email, password, role) => {
    const data = await api.signup({ name, email, password, role });
    localStorage.setItem("stocksense_token", data.access_token);
    const userObj = { name: data.user_name, role: data.role, email };
    localStorage.setItem("stocksense_user", JSON.stringify(userObj));
    setUser(userObj);
    return userObj;
  }, []);

  const logout = useCallback(() => {
    localStorage.removeItem("stocksense_token");
    localStorage.removeItem("stocksense_user");
    setUser(null);
  }, []);

  return (
    <AuthContext.Provider value={{ user, login, signup, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  return useContext(AuthContext);
}
