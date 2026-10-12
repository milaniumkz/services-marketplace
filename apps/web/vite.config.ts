import { defineConfig } from "vite";
export default defineConfig({server:{port:5175,strictPort:true,proxy:{"/api":"http://127.0.0.1:3000"}},build:{rollupOptions:{input:["index.html","W01.html","W02.html","W03.html","W04.html","W05.html"]}}});
