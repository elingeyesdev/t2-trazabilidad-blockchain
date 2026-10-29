import { defineConfig } from 'vite';
import laravel from 'laravel-vite-plugin';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
    plugins: [
        laravel({
            input: ['resources/css/app.css', 'resources/js/app.js', 'resources/css/tabler-lotes.css', 'resources/js/tabler-lotes.js'],
            refresh: true,
        }),
        tailwindcss(),
    ],
});
