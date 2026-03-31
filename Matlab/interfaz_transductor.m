function interfaz_transductor()
% INTERFAZ_TRANSDUCTOR  Adquisición y guardado para transductor piezoeléctrico
%
% Recibe LONGITUD=2000 floats en ASCII via UART del PSoC (CY8CKIT-059).
% Guarda cada medición en archivos .mat separados por pilote dentro de una
% carpeta seleccionable por el usuario.
%
% ── PROTOCOLO SERIAL (ASCII, un float por línea) ──────────────────────────
%   S<LF>          ← inicio de trama  (opcional)
%   1.2345<LF>     ← LONGITUD floats, uno por línea
%   ...
%   E<LF>          ← fin de trama  (se cierra solo al llegar a LONGITUD)
%
%   Si el PSoC no envía marcadores S/E, la trama se detecta automáticamente
%   al recibir LONGITUD valores numéricos consecutivos.
%   El botón DISPARAR envía el byte 'T' al PSoC para solicitar adquisición.
%
% ── ESTRUCTURA GUARDADA EN .mat (un archivo por pilote) ────────────────────
%   pilote_info.nombre      string  — identificador del pilote
%   pilote_info.stickup     double  — stickup del pivote [m]
%   pilote_info.fecha_reg   string  — fecha de registro del pilote
%
%   pilote_datos(i).pilote       string  — identificador del pilote
%   pilote_datos(i).profundidad  double  — profundidad [m]
%   pilote_datos(i).stickup      double  — stickup del pivote [m]
%   pilote_datos(i).senal        Nx1     — señal ADC convertida a voltios
%   pilote_datos(i).tiempo       Nx1     — eje de tiempo [ms]
%   pilote_datos(i).fs           double  — frecuencia de muestreo [Hz]
%   pilote_datos(i).fecha        string  — timestamp de adquisición
%   pilote_datos(i).n_muestras   int     — cantidad de muestras recibidas
%
% ── LÓGICA DE GUARDADO ─────────────────────────────────────────────────────
%   Cada pilote tiene su propio .mat en la carpeta de datos.
%   Tags iguales  (pilote + profundidad + stickup) → sobreescribe
%   Tags distintos                                 → append
%
% Requiere MATLAB R2019b+ (serialport API).
% ──────────────────────────────────────────────────────────────────────────

% =========================================================================
% Constantes
% =========================================================================
LONGITUD      = 2000;
BAUD_VALS     = [9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600];
BAUD_STRS     = {'9600','19200','38400','57600','115200','230400','460800','921600'};
DEF_BAUD_IDX  = 5;   % 115200
PLOT_COLORS   = {[0.12 0.40 0.82], [0.82 0.18 0.14], [0.15 0.65 0.20], ...
                 [0.88 0.52 0.08], [0.55 0.20 0.75], [0.10 0.70 0.70], ...
                 [0.70 0.45 0.10], [0.80 0.10 0.60]};
STAT_YPOS     = [0.82 0.64 0.46 0.28 0.10];
% Paleta de colores
C_BG  = [0.93 0.93 0.93];
C_GRN = [0.15 0.65 0.20];
C_RED = [0.82 0.18 0.14];
C_BLU = [0.12 0.40 0.82];
C_ORG = [0.88 0.52 0.08];
C_WHT = [1.00 1.00 1.00];

% =========================================================================
% Figura principal
% =========================================================================
fig = figure( ...
    'Name',            'Interfaz Transductor de Presión – Pozos', ...
    'NumberTitle',     'off', ...
    'Position',        [30 30 1260 830], ...
    'Resize',          'on', ...
    'Color',           C_BG, ...
    'CloseRequestFcn', @onClose);

% =========================================================================
% Estado de la aplicación  (compartido mediante guidata)
% =========================================================================
% Anclar la carpeta de datos al directorio donde vive este script
script_dir     = fileparts(mfilename('fullpath'));
def_matfolder  = fullfile(script_dir, 'datos_pozos');
config_file    = fullfile(script_dir, 'config_interfaz.mat');
if ~isfolder(def_matfolder); mkdir(def_matfolder); end

app.LONGITUD   = LONGITUD;
app.serial_obj = [];
app.connected  = false;
app.receiving  = false;
app.in_frame   = false;
app.rx_floats  = zeros(1, LONGITUD);
app.rx_count   = 0;
app.cur_signal  = [];
app.cur_time    = [];
app.live_signal    = [];   % señal recibida por serial (única que se puede guardar)
app.live_time      = [];
app.mat_folder     = def_matfolder;
app.pilotes        = [];
app.plot_lines     = {};
app.tree_groups    = {};   % cell: tree_groups{i} = vector de índices datos en ese ítem ([] si vacío/placeholder)
app.tree_items_base = {}; % strings base del árbol (sin marcadores de cargado)
app.loaded_data_idxs = []; % índices de datos actualmente cargados en plot (en orden de slot/color)
app.loaded_signals = {};          % {struct(signal,time,color,label)} señales en plot

% =========================================================================
% ── Panel 1: Conexión Serial ─────────────────────────  arriba-izquierda
% =========================================================================
pp = mkpanel(fig, ' Conexión Serial', [0.005 0.775 0.235 0.215]);

mktext(pp, 'Puerto:',    [0.04 0.72 0.28 0.18]);
mktext(pp, 'Baud rate:', [0.04 0.46 0.28 0.18]);

avail_ports = cellstr(serialportlist('available'));
if isempty(avail_ports)
    port_labels = {'(sin puertos)'};
else
    port_labels = getPortLabels(avail_ports);
end
ui.pop_port = uicontrol(pp, 'Style', 'popupmenu', ...
    'String', port_labels, 'Value', 1, ...
    'Units', 'normalized', 'Position', [0.33 0.72 0.49 0.18]);
ui.btn_refresh_port = mkbtn(pp, char(8635), [0.84 0.72 0.13 0.18], C_BG(1,:), @onRefreshPorts);
ui.pop_baud  = uicontrol(pp, 'Style', 'popupmenu', ...
    'String', BAUD_STRS, 'Value', DEF_BAUD_IDX, ...
    'Units', 'normalized', 'Position', [0.33 0.46 0.64 0.18]);

ui.btn_connect = mkbtn(pp, 'CONECTAR', [0.06 0.20 0.88 0.21], C_GRN, @onConnectBtn);

ui.lbl_conn = uicontrol(pp, 'Style', 'text', ...
    'String', 'Desconectado', ...
    'Units', 'normalized', 'Position', [0.04 0.01 0.92 0.17], ...
    'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
    'ForegroundColor', C_RED, 'BackgroundColor', C_BG);

% =========================================================================
% ── Panel 2: Metadata ────────────────────────────────  arriba-centro
% =========================================================================
pp = mkpanel(fig, ' Metadata de Medición', [0.248 0.775 0.455 0.215]);

% ── Fila 1: Gestión de Pilotes (prominente) ────────────────────────────
mktext(pp, 'Pilote:',      [0.02 0.65 0.18 0.22]);
ui.pop_pilote = uicontrol(pp, 'Style', 'popupmenu', ...
    'String', {'(sin pilotes)'}, 'Value', 1, ...
    'Units', 'normalized', 'Position', [0.21 0.65 0.38 0.22], ...
    'Callback', @onPiloteChanged, 'FontSize', 10);
ui.btn_new_pilote = mkbtn(pp, sprintf('⚙ GESTIONAR\nPILOTES'), [0.61 0.63 0.37 0.26], C_ORG, @onNewPilote);

% ── Fila 2: Profundidad, Stickup ────────────────────────────────────────
mktext(pp, 'Profundidad:', [0.02 0.40 0.18 0.18]);
ui.edit_prof = mkedit(pp, '0.0', [0.21 0.41 0.15 0.19]);
mktext(pp, 'm', [0.37 0.41 0.04 0.18]);

mktext(pp, 'Stickup:',     [0.52 0.40 0.18 0.18]);
ui.lbl_stickup_val = uicontrol(pp, 'Style', 'text', 'String', '—', ...
    'Units', 'normalized', 'Position', [0.71 0.41 0.15 0.19], ...
    'HorizontalAlignment', 'center', 'FontWeight', 'bold', 'FontSize', 10, ...
    'BackgroundColor', [0.95 0.95 0.95]);
mktext(pp, 'm', [0.87 0.41 0.04 0.18]);

% ── Fila 3: Frec. muestreo, Puntos, Carpeta ────────────────────────────
mktext(pp, 'Frec. (Hz):', [0.02 0.15 0.14 0.18]);
ui.edit_fs = mkedit(pp, '10000', [0.17 0.16 0.12 0.19]);

mktext(pp, 'Puntos:',     [0.31 0.15 0.09 0.18]);
ui.edit_longitud = mkedit(pp, num2str(LONGITUD), [0.40 0.16 0.09 0.19]);

mktext(pp, 'Carpeta:',    [0.51 0.15 0.10 0.18]);
ui.edit_matfile = mkedit(pp, def_matfolder, [0.62 0.16 0.25 0.19]);
mkbtn(pp, '...', [0.88 0.16 0.10 0.19], C_BG(1,:), @onBrowse);

% Info
ui.lbl_nrec = uicontrol(pp, 'Style', 'text', ...
    'String', 'Registros: 0', ...
    'Units', 'normalized', 'Position', [0.02 0.00 0.96 0.12], ...
    'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
    'BackgroundColor', C_BG);

% =========================================================================
% ── Panel 3: Control de Adquisición ─────────────────  arriba-derecha
% =========================================================================
pp = mkpanel(fig, ' Control de Adquisición', [0.712 0.775 0.283 0.215]);

ui.btn_trigger = mkbtn(pp, sprintf('DISPARAR\nADQUISICIÓN'), ...
    [0.04 0.42 0.45 0.52], C_BLU, @onTrigger);
ui.btn_save    = mkbtn(pp, sprintf('GUARDAR\n  SEÑAL'), ...
    [0.53 0.42 0.43 0.52], C_ORG, @onSave);
set([ui.btn_trigger ui.btn_save], 'Enable', 'off');

ui.lbl_status = uicontrol(pp, 'Style', 'text', ...
    'String', 'Estado: Desconectado', ...
    'Units', 'normalized', 'Position', [0.03 0.22 0.94 0.18], ...
    'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
    'BackgroundColor', C_BG);

ui.lbl_samples = uicontrol(pp, 'Style', 'text', ...
    'String', 'Muestras: —', ...
    'Units', 'normalized', 'Position', [0.03 0.03 0.94 0.17], ...
    'HorizontalAlignment', 'left', 'BackgroundColor', C_BG);

% =========================================================================
% ── Panel 4: Plot principal ──────────────────────────  centro-izquierda
% =========================================================================
pp = mkpanel(fig, ' Señal Adquirida', [0.005 0.225 0.70 0.545]);

ui.ax = axes('Parent', pp, ...
    'Units', 'normalized', 'Position', [0.09 0.13 0.88 0.82], ...
    'Box', 'on', ...
    'XGrid', 'on', ...
    'YGrid', 'on', ...
    'XMinorGrid', 'on', ...
    'YMinorGrid', 'on', ...
    'XMinorTick', 'on', ...
    'YMinorTick', 'on', ...
    'Layer', 'top');

xlabel(ui.ax, 'Tiempo (ms)', 'FontSize', 10);
ylabel(ui.ax, 'Amplitud (V)', 'FontSize', 10);
title(ui.ax, 'Sin datos — conectar y disparar adquisición', 'FontSize', 10);

ui.ax.GridAlpha      = 0.25;
ui.ax.MinorGridAlpha = 0.12;
ui.hline = plot(ui.ax, NaN, NaN, 'Color', PLOT_COLORS{1}, 'LineWidth', 1.3);

% =========================================================================
% ── Panel 5: Estadísticas de señal ──────────────────  centro-derecha-top
% =========================================================================
pp = mkpanel(fig, ' Estadísticas', [0.713 0.500 0.282 0.270]);


stat_names = {'Máx (V):', 'Mín (V):', 'Media (V):', 'RMS (V):', 'Duración (ms):'};
for s_i = 1:5
    mktext(pp, stat_names{s_i}, [0.03 STAT_YPOS(s_i) 0.26 0.14]);
end
% Pre-crear hasta 8 value-labels por fila (uno por curva), coloreados dinámicamente
NMAX_C = length(PLOT_COLORS);
for s_i = 1:5
    for k_i = 1:NMAX_C
        ui.stat_vals{s_i, k_i} = uicontrol(pp, 'Style', 'text', ...
            'String', '', 'Visible', 'off', ...
            'Units', 'normalized', 'Position', [0.57 STAT_YPOS(s_i) 0.40 0.14], ...
            'FontSize', 8.5, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', ...
            'BackgroundColor', C_BG, 'ForegroundColor', [0 0 0]);
    end
end

% =========================================================================
% ── Panel 6: Zoom ────────────────────────────────────  abajo-izquierda
% =========================================================================
pp = mkpanel(fig, ' Zoom', [0.005 0.010 0.52 0.208]);

mktext(pp, 'Tiempo (ms):', [0.01 0.64 0.09 0.22]);
mktext(pp, 'Desde:',       [0.11 0.64 0.05 0.22]);
ui.edit_t0 = mkedit(pp, '', [0.17 0.64 0.10 0.22]);
mktext(pp, 'Hasta:',       [0.28 0.64 0.05 0.22]);
ui.edit_t1 = mkedit(pp, '', [0.34 0.64 0.10 0.22]);

mktext(pp, 'Amplitud (V):', [0.01 0.34 0.09 0.22]);
mktext(pp, 'Desde:',        [0.11 0.34 0.05 0.22]);
ui.edit_v0 = mkedit(pp, '', [0.17 0.34 0.10 0.22]);
mktext(pp, 'Hasta:',        [0.28 0.34 0.05 0.22]);
ui.edit_v1 = mkedit(pp, '', [0.34 0.34 0.10 0.22]);

mkbtn(pp, 'Aplicar', [0.78 0.56 0.18 0.24], C_BLU,     @onZoomApply, 8);
mkbtn(pp, 'Reset',   [0.78 0.22 0.18 0.24], C_BG(1,:), @onZoomReset, 8);
% =========================================================================
% ── Panel 7: Registros guardados ────────────────────  derecha-arriba
% =========================================================================
pp = mkpanel(fig, ' Registros guardados', [0.713 0.010 0.282 0.512]);

ui.list_rec = uicontrol(pp, 'Style', 'listbox', ...
    'Units', 'normalized', 'Position', [0.02 0.02 0.96 0.96], ...
    'String', {}, 'FontSize', 8, 'BackgroundColor', C_WHT, ...
    'FontName', 'Courier New', ...
    'Min', 0, 'Max', 2);
% =========================================================================
% ── Panel 8: Acciones (al lado del Zoom) ────────────  derecha-abajo
% =========================================================================
pp = mkpanel(fig, ' Acciones', [0.535 0.010 0.170 0.208]);

mkbtn(pp, 'Cargar / Descargar',   [0.06 0.68 0.88 0.22], C_BG(1,:), @onLoadRecord, 8);
mkbtn(pp, 'Deseleccionar todos',  [0.06 0.38 0.88 0.22], C_ORG,     @onClearLoaded, 8);
mkbtn(pp, 'BORRAR',               [0.06 0.08 0.88 0.22], C_RED,     @onDeleteRecord, 8);
% =========================================================================
% Guardar estado
% =========================================================================
app.ui = ui;
guidata(fig, app);

% ── Restaurar configuración de sesión anterior ──────────────────────────
loadConfig();

refreshPilotesList();
refreshRecordsList();

% #########################################################################
% CALLBACKS
% #########################################################################

% ── Conectar / Desconectar ───────────────────────────────────────────────
    function onConnectBtn(~, ~)
        app = guidata(fig);
        if app.connected
            doDisconnect();
        else
            doConnect();
        end
    end

    function doConnect()
        app  = guidata(fig);
        labels = get(app.ui.pop_port, 'String');
        if ischar(labels); labels = {labels}; end
        label = labels{get(app.ui.pop_port, 'Value')};
        parts = strsplit(label, ' – ');
        port  = strtrim(parts{1});
        baud = BAUD_VALS(get(app.ui.pop_baud, 'Value'));
        try
            s = serialport(port, baud, 'Timeout', 2);
            configureTerminator(s, 'LF');
            flush(s);
            configureCallback(s, 'terminator', @serialRxCb);

            app.serial_obj = s;
            app.connected  = true;
            app.rx_count   = 0;
            app.in_frame   = false;
            app.receiving  = false;

            set(app.ui.btn_connect, 'String', 'DESCONECTAR', 'BackgroundColor', C_RED);
            set(app.ui.lbl_conn,    'String', ['Conectado: ' port], ...
                'ForegroundColor', [0 0.55 0.10]);
            set(app.ui.btn_trigger, 'Enable', 'on');
            set(app.ui.lbl_status,  'String', 'Estado: Conectado — Listo', ...
                'ForegroundColor', [0 0 0]);
            guidata(fig, app);
        catch err
            errordlg(sprintf('No se pudo abrir %s:\n%s', port, err.message), ...
                'Error de Conexión');
        end
    end

    function doDisconnect()
        app = guidata(fig);
        try
            if ~isempty(app.serial_obj) && isvalid(app.serial_obj)
                configureCallback(app.serial_obj, 'off');
                delete(app.serial_obj);
            end
        catch
        end

        app.serial_obj = [];
        app.connected  = false;
        app.receiving  = false;
        app.in_frame   = false;
        app.rx_count   = 0;

        set(app.ui.btn_connect, 'String', 'CONECTAR',     'BackgroundColor', C_GRN);
        set(app.ui.lbl_conn,    'String', 'Desconectado', 'ForegroundColor', C_RED);
        set([app.ui.btn_trigger app.ui.btn_save], 'Enable', 'off');
        set(app.ui.lbl_status,  'String', 'Estado: Desconectado', 'ForegroundColor', [0 0 0]);
        set(app.ui.lbl_samples, 'String', 'Muestras: —');
        guidata(fig, app);
    end

% ── Recepción serial (callback por línea) ───────────────────────────────
    function serialRxCb(src, ~)
        app = guidata(fig);
        try
            line = strtrim(char(readline(src)));
        catch
            return;
        end
        if isempty(line); return; end

        % ── Marcador inicio de trama ──
        if strcmpi(line, 'S') || strcmpi(line, 'START')
            app.rx_count  = 0;
            app.rx_floats = zeros(1, app.LONGITUD);
            app.in_frame  = true;
            app.receiving = true;
            set(app.ui.lbl_status, 'String', 'Estado: RECIBIENDO...', ...
                'ForegroundColor', C_ORG);
            set(app.ui.lbl_samples, 'String', sprintf('Muestras: 0 / %d', app.LONGITUD));
            guidata(fig, app);
            return;
        end

        % ── Marcador fin de trama ──
        if strcmpi(line, 'E') || strcmpi(line, 'END')
            app.in_frame  = false;
            app.receiving = false;
            if app.rx_count > 0
                app = closeFrame(app);
            end
            guidata(fig, app);
            return;
        end

        % ── Valor numérico ──
        val = str2double(line);
        if isnan(val); guidata(fig, app); return; end

        % Auto-inicio de trama sin marcadores
        if ~app.in_frame
            app.rx_count  = 0;
            app.rx_floats = zeros(1, app.LONGITUD);
            app.in_frame  = true;
            app.receiving = true;
            set(app.ui.lbl_status, 'String', 'Estado: RECIBIENDO (auto)...', ...
                'ForegroundColor', C_ORG);
        end

        if app.rx_count < app.LONGITUD
            app.rx_count = app.rx_count + 1;
            app.rx_floats(app.rx_count) = val;

            if mod(app.rx_count, 50) == 0
                pct = round(100 * app.rx_count / app.LONGITUD);
                set(app.ui.lbl_samples, 'String', ...
                    sprintf('Muestras: %d / %d  (%d%%)', ...
                    app.rx_count, app.LONGITUD, pct));
                drawnow limitrate;
            end

            % Cierre automático al completar LONGITUD muestras
            if app.rx_count >= app.LONGITUD
                app.in_frame  = false;
                app.receiving = false;
                app = closeFrame(app);
            end
        end

        guidata(fig, app);
    end

% ── Procesar trama completa ──────────────────────────────────────────────
    function app = closeFrame(app)
        n      = app.rx_count;
        fs_val = str2double(get(app.ui.edit_fs, 'String'));
        if isnan(fs_val) || fs_val <= 0; fs_val = 10000; end

        sig = app.rx_floats(1:n)';
        t   = ((0:n-1) / fs_val * 1000)';

        app.live_signal    = sig;   % señal del PSoC (fuente única para guardar)
        app.live_time      = t;
        app.cur_signal     = sig;
        app.cur_time       = t;
        app.loaded_signals = {struct('signal', sig, 'time', t, ...
            'color', PLOT_COLORS{1}, 'label', 'Adquirida PSoC')};
        app.loaded_data_idxs = [];

        doUpdatePlot(app);
        doUpdateStats(app);
        renderTreeItems(app);

        set(app.ui.lbl_status, 'String', ...
            sprintf('Estado: Listo — %d muestras @ %.0f Hz', n, fs_val), ...
            'ForegroundColor', C_GRN);
        set(app.ui.lbl_samples, 'String', ...
            sprintf('Muestras: %d / %d', n, app.LONGITUD));
        set(app.ui.btn_save, 'Enable', 'on');
    end

% ── Disparar adquisición ─────────────────────────────────────────────────
    function onTrigger(~, ~)
        app = guidata(fig);
        if ~app.connected || isempty(app.serial_obj); return; end
        if app.receiving; return; end

        lng = round(str2double(get(app.ui.edit_longitud, 'String')));
        if ~isnan(lng) && lng > 0
            app.LONGITUD  = lng;
            app.rx_floats = zeros(1, lng);
        end

        app.rx_count  = 0;
        app.in_frame  = false;
        app.receiving = false;

        try
            write(app.serial_obj, uint8('T'), 'uint8');
        catch err
            % Si el PSoC no implementa recepción de T, continúa en modo escucha
            fprintf('Advertencia al enviar trigger: %s\n', err.message);
        end

        set(app.ui.lbl_status, 'String', ...
            'Estado: Trigger enviado — Esperando trama...', ...
            'ForegroundColor', [0.45 0 0.65]);
        set(app.ui.lbl_samples, 'String', sprintf('Muestras: 0 / %d', app.LONGITUD));
        guidata(fig, app);
    end

% ── Guardar señal en .mat ────────────────────────────────────────────────
    function onSave(~, ~)
        app = guidata(fig);
        if isempty(app.live_signal)
            warndlg('No hay señal del PSoC para guardar. Adquirí una señal primero.', 'Aviso'); return;
        end

        % Leer pilote seleccionado en el popup
        [nombre_pilote, stk] = getSelectedPilote(app);
        if isempty(nombre_pilote)
            warndlg('Registrá al menos un pilote antes de guardar.', 'Aviso'); return;
        end

        prof   = str2double(get(app.ui.edit_prof,    'String'));
        fs_val = str2double(get(app.ui.edit_fs,      'String'));
        mfolder = strtrim(get(app.ui.edit_matfile, 'String'));

        if isnan(prof);    prof   = 0;                end
        if isnan(fs_val);  fs_val = 10000;            end
        if isempty(mfolder); mfolder = def_matfolder; end

        % Construir registro — siempre append, la fecha diferencia las mediciones
        nuevo.pilote      = nombre_pilote;
        nuevo.profundidad = prof;
        nuevo.stickup     = stk;
        nuevo.fs          = fs_val;
        nuevo.senal       = app.live_signal;
        nuevo.tiempo      = app.live_time;
        nuevo.fecha       = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
        nuevo.n_muestras  = length(app.cur_signal);

        % Cargar datos existentes del pilote
        pilote_datos = loadPiloteDatos(mfolder, nombre_pilote);

        if isempty(pilote_datos)
            pilote_datos = nuevo;
        else
            pilote_datos(end+1) = nuevo;
        end

        try
            pilote_info = getPiloteInfoByName(mfolder, nombre_pilote);
            savePiloteFile(mfolder, pilote_info, pilote_datos);
            app.mat_folder = mfolder;
            guidata(fig, app);
            set(app.ui.lbl_status, 'String', ...
                sprintf('Estado: GUARDADO — %s @ %.2f m  [%s]', ...
                nombre_pilote, prof, nuevo.fecha), ...
                'ForegroundColor', C_BLU);
            refreshRecordsList();
        catch err
            errordlg(['Error al guardar: ' err.message], 'Error');
        end
    end

% ── Examinar archivo .mat ────────────────────────────────────────────────
    function onBrowse(~, ~)
        folder = uigetdir(def_matfolder, 'Seleccionar carpeta de datos');
        if isequal(folder, 0); return; end
        app = guidata(fig);
        set(app.ui.edit_matfile, 'String', folder);
        app.mat_folder = folder;
        guidata(fig, app);
        refreshPilotesList();
        refreshRecordsList();
    end

% ── Zoom ─────────────────────────────────────────────────────────────────
    function onZoomApply(~, ~)
        app = guidata(fig);
        t0 = str2double(get(app.ui.edit_t0, 'String'));
        t1 = str2double(get(app.ui.edit_t1, 'String'));
        v0 = str2double(get(app.ui.edit_v0, 'String'));
        v1 = str2double(get(app.ui.edit_v1, 'String'));
        applied = false;
        if ~isnan(t0) && ~isnan(t1) && t0 < t1
            xlim(app.ui.ax, [t0 t1]); applied = true;
        end
        if ~isnan(v0) && ~isnan(v1) && v0 < v1
            ylim(app.ui.ax, [v0 v1]); applied = true;
        end
        if ~applied
            warndlg('Ingrese al menos un rango válido (Desde < Hasta).', 'Zoom');
        end
    end

    function onZoomReset(~, ~)
        app = guidata(fig);
        xlim(app.ui.ax, 'auto');
        ylim(app.ui.ax, 'auto');
        drawnow;
        xl = xlim(app.ui.ax);
        yl = ylim(app.ui.ax);
        if isfinite(xl(1))
            set(app.ui.edit_t0, 'String', sprintf('%.3f', xl(1)));
            set(app.ui.edit_t1, 'String', sprintf('%.3f', xl(2)));
        elseif ~isempty(app.cur_time)
            set(app.ui.edit_t0, 'String', '0');
            set(app.ui.edit_t1, 'String', sprintf('%.3f', app.cur_time(end)));
        end
        if isfinite(yl(1))
            set(app.ui.edit_v0, 'String', sprintf('%.4f', yl(1)));
            set(app.ui.edit_v1, 'String', sprintf('%.4f', yl(2)));
        else
            set(app.ui.edit_v0, 'String', '');
            set(app.ui.edit_v1, 'String', '');
        end

        forceGrid(app.ui.ax);
    end

% ── Cargar registro(s) seleccionado(s) ──────────────────────────────────
    function onLoadRecord(~, ~)
        app   = guidata(fig);
        mfolder = strtrim(get(app.ui.edit_matfile, 'String'));
        if ~isfolder(mfolder)
            warndlg('Carpeta de datos no encontrada.', 'Aviso'); return;
        end

        datos = loadAllDatos(mfolder);
        if isempty(datos)
            warndlg('No hay registros en el archivo.', 'Aviso'); return;
        end

        % Expandir selección usando tree_groups
        raw_sels = get(app.ui.list_rec, 'Value');
        tg = app.tree_groups;
        sel_idxs = [];
        for si = 1:length(raw_sels)
            s = raw_sels(si);
            if s >= 1 && s <= length(tg) && ~isempty(tg{s})
                sel_idxs = [sel_idxs, tg{s}(:)']; %#ok<AGROW>
            end
        end
        sel_idxs = unique(sel_idxs);
        % Filtrar índices fuera de rango
        sel_idxs = sel_idxs(sel_idxs >= 1 & sel_idxs <= length(datos));
        if isempty(sel_idxs)
            warndlg('Seleccione mediciones o grupos con registros.', 'Aviso'); return;
        end

        try
            % Toggle: quitar los que ya están cargados, agregar los que no están
            already  = intersect(sel_idxs, app.loaded_data_idxs);
            to_add   = setdiff(sel_idxs,   app.loaded_data_idxs);
            new_loaded = unique([setdiff(app.loaded_data_idxs, already), to_add]);

            if isempty(new_loaded)
                % Se quitaron todos → limpiar plot
                app.loaded_data_idxs = [];
                app.loaded_signals   = {};
                for k = 1:length(app.plot_lines)
                    try; if isvalid(app.plot_lines{k}); delete(app.plot_lines{k}); end; catch; end
                end
                app.plot_lines = {};
                legend(app.ui.ax, 'off');
                if ~isempty(app.live_signal)
                    app.cur_signal     = app.live_signal;
                    app.cur_time       = app.live_time;
                    app.loaded_signals = {struct('signal', app.live_signal, 'time', app.live_time, ...
                        'color', PLOT_COLORS{1}, 'label', 'Adquirida PSoC')};
                    guidata(fig, app);
                    doUpdatePlot(app);
                else
                    app.cur_signal = [];
                    app.cur_time   = [];
                    set(app.ui.hline, 'XData', NaN, 'YData', NaN);
                    title(app.ui.ax, 'Sin datos', 'FontSize', 10);
                    guidata(fig, app);
                end
                app = guidata(fig);
                doUpdateStats(app);
                renderTreeItems(app);
                set(app.ui.lbl_status, 'String', 'Señales descargadas.', 'ForegroundColor', C_ORG);
                return;
            end

            % Actualizar metadata con la última señal agregada (o última de new_loaded)
            ref_idx = new_loaded(end);
            rec = datos(ref_idx);
            set(app.ui.edit_prof, 'String', num2str(rec.profundidad));
            set(app.ui.edit_fs,   'String', num2str(rec.fs));
            nombres = get(app.ui.pop_pilote, 'String');
            match   = find(strcmpi(nombres, rec.pilote), 1);
            if ~isempty(match)
                set(app.ui.pop_pilote, 'Value', match);
                onPiloteChanged([], []);
                app = guidata(fig);
            end

            app.loaded_data_idxs = new_loaded;
            guidata(fig, app);
            doMultiPlot(app, datos, new_loaded);
            % doUpdateStats y renderTreeItems ya son llamados dentro de doMultiPlot

            if length(new_loaded) == 1
                set(app.ui.lbl_status, 'String', ...
                    sprintf('Cargado: %s @ %.2f m  —  %s', ...
                    rec.pilote, rec.profundidad, rec.fecha), ...
                    'ForegroundColor', C_BLU);
            else
                set(app.ui.lbl_status, 'String', ...
                    sprintf('%d señales en plot', length(new_loaded)), ...
                    'ForegroundColor', C_BLU);
            end
        catch err
            errordlg(['Error: ' err.message], 'Error');
        end
    end



% ── Refresh lista de puertos disponibles ─────────────────────────────────
    function onRefreshPorts(~, ~)
        app = guidata(fig);
        new_ports = cellstr(serialportlist('available'));
        if isempty(new_ports)
            new_labels = {'(sin puertos)'};
        else
            new_labels = getPortLabels(new_ports);
        end
        % Conservar selección anterior: extraer solo el nombre COM
        cur_labels = get(app.ui.pop_port, 'String');
        if ischar(cur_labels); cur_labels = {cur_labels}; end
        cur_parts = strsplit(cur_labels{get(app.ui.pop_port, 'Value')}, ' – ');
        cur_port  = strtrim(cur_parts{1});
        set(app.ui.pop_port, 'String', new_labels, 'Value', 1);
        for k = 1:length(new_ports)
            if strcmp(new_ports{k}, cur_port)
                set(app.ui.pop_port, 'Value', k); break;
            end
        end
    end

% ── Borrar registros seleccionados del .mat ──────────────────────────────
    function onDeleteRecord(~, ~)
        app   = guidata(fig);
        mfolder = strtrim(get(app.ui.edit_matfile, 'String'));
        if ~isfolder(mfolder)
            warndlg('Carpeta de datos no encontrada.', 'Aviso'); return;
        end

        datos = loadAllDatos(mfolder);
        if isempty(datos); return; end

        raw_sels = get(app.ui.list_rec, 'Value');
        tg = app.tree_groups;
        data_idxs = [];
        for si = 1:length(raw_sels)
            s = raw_sels(si);
            if s >= 1 && s <= length(tg) && ~isempty(tg{s})
                data_idxs = [data_idxs, tg{s}(:)']; %#ok<AGROW>
            end
        end
        data_idxs = unique(data_idxs);
        if isempty(data_idxs)
            warndlg('Seleccione mediciones o grupos para eliminar.', 'Aviso'); return;
        end

        if length(data_idxs) == 1
            rec = datos(data_idxs(1));
            msg = sprintf('¿Eliminar el registro [%d] %s @ %.2f m (%s)?', ...
                data_idxs(1), rec.pilote, rec.profundidad, rec.fecha);
        else
            msg = sprintf('¿Eliminar %d registros seleccionados?', length(data_idxs));
        end

        confirm = questdlg(msg, 'Confirmar eliminación', 'Eliminar', 'Cancelar', 'Cancelar');
        if ~strcmp(confirm, 'Eliminar'); return; end

        % Identificar pilotes afectados
        affected_pilotes = unique({datos(data_idxs).pilote});

        mask = true(1, length(datos));
        mask(data_idxs) = false;
        datos_remaining = datos(mask);

        try
            for ap = 1:length(affected_pilotes)
                pname = affected_pilotes{ap};
                pilote_info = getPiloteInfoByName(mfolder, pname);
                if isempty(datos_remaining)
                    pilote_datos = []; %#ok<NASGU>
                else
                    pmask = strcmp({datos_remaining.pilote}, pname);
                    pilote_datos = datos_remaining(pmask); %#ok<NASGU>
                end
                savePiloteFile(mfolder, pilote_info, pilote_datos);
            end
            set(app.ui.lbl_status, 'String', ...
                sprintf('%d registro(s) eliminado(s).', length(data_idxs)), ...
                'ForegroundColor', C_ORG);
            refreshRecordsList();
        catch err
            errordlg(['Error al guardar: ' err.message], 'Error');
        end
    end

% ── Limpiar señales cargadas del .mat ────────────────────────────────────
    function onClearLoaded(~, ~)
        app = guidata(fig);
        % Eliminar líneas de multi-plot
        for k = 1:length(app.plot_lines)
            try; if isvalid(app.plot_lines{k}); delete(app.plot_lines{k}); end; catch; end
        end
        app.plot_lines = {};
        legend(app.ui.ax, 'off');
        app.loaded_data_idxs = [];
        guidata(fig, app);
        set(app.ui.list_rec, 'Value', []);
        

        if ~isempty(app.live_signal)
            app.cur_signal     = app.live_signal;
            app.cur_time       = app.live_time;
            app.loaded_signals = {struct('signal', app.live_signal, 'time', app.live_time, ...
                'color', PLOT_COLORS{1}, 'label', 'Adquirida PSoC')};
            guidata(fig, app);
            renderTreeItems(app);
            doUpdatePlot(app);
            doUpdateStats(app);
            set(app.ui.lbl_status, 'String', ...
                'Señal del PSoC restaurada.', 'ForegroundColor', C_BLU);
        else
            app.cur_signal     = [];
            app.cur_time       = [];
            app.loaded_signals = {};
            set(app.ui.hline, 'XData', NaN, 'YData', NaN);
            title(app.ui.ax, 'Sin datos — conectar y disparar adquisición', 'FontSize', 10);
            set(app.ui.lbl_status, 'String', ...
                'Deseleccionado.', 'ForegroundColor', C_ORG);
            guidata(fig, app);
            renderTreeItems(app);
            doUpdateStats(app);
        end
    end

% ── Cierre de figura ─────────────────────────────────────────────────────
    function onClose(~, ~)
        app = guidata(fig);
        saveConfig();
        try
            if ~isempty(app.serial_obj) && isvalid(app.serial_obj)
                configureCallback(app.serial_obj, 'off');
                delete(app.serial_obj);
            end
        catch
        end
        delete(fig);
    end

% ── Guardar / Restaurar configuración de sesión ─────────────────────────
    function saveConfig()
        app = guidata(fig);
        try
            cfg.mat_folder   = strtrim(get(app.ui.edit_matfile, 'String'));
            cfg.baud_idx     = get(app.ui.pop_baud, 'Value');
            cfg.port_idx     = get(app.ui.pop_port, 'Value');
            cfg.fs           = strtrim(get(app.ui.edit_fs, 'String'));
            cfg.longitud     = strtrim(get(app.ui.edit_longitud, 'String'));
            cfg.profundidad  = strtrim(get(app.ui.edit_prof, 'String'));
            cfg.pilote_idx   = get(app.ui.pop_pilote, 'Value');
            cfg.fig_position = get(fig, 'Position');
            cfg.zoom_t0      = strtrim(get(app.ui.edit_t0, 'String'));
            cfg.zoom_t1      = strtrim(get(app.ui.edit_t1, 'String'));
            cfg.zoom_v0      = strtrim(get(app.ui.edit_v0, 'String'));
            cfg.zoom_v1      = strtrim(get(app.ui.edit_v1, 'String'));
            save(config_file, 'cfg'); %#ok<NASGU>
        catch
        end
    end

    function loadConfig()
        if exist(config_file, 'file') ~= 2; return; end
        try
            tmp = load(config_file, 'cfg');
            cfg = tmp.cfg;
        catch
            return;
        end
        app = guidata(fig);
        try
            if isfield(cfg, 'mat_folder') && ~isempty(cfg.mat_folder)
                set(app.ui.edit_matfile, 'String', cfg.mat_folder);
                app.mat_folder = cfg.mat_folder;
            end
            if isfield(cfg, 'baud_idx')
                nopt = length(get(app.ui.pop_baud, 'String'));
                if cfg.baud_idx >= 1 && cfg.baud_idx <= nopt
                    set(app.ui.pop_baud, 'Value', cfg.baud_idx);
                end
            end
            if isfield(cfg, 'port_idx')
                nopt = length(get(app.ui.pop_port, 'String'));
                if cfg.port_idx >= 1 && cfg.port_idx <= nopt
                    set(app.ui.pop_port, 'Value', cfg.port_idx);
                end
            end
            if isfield(cfg, 'fs') && ~isempty(cfg.fs)
                set(app.ui.edit_fs, 'String', cfg.fs);
            end
            if isfield(cfg, 'longitud') && ~isempty(cfg.longitud)
                set(app.ui.edit_longitud, 'String', cfg.longitud);
            end
            if isfield(cfg, 'profundidad') && ~isempty(cfg.profundidad)
                set(app.ui.edit_prof, 'String', cfg.profundidad);
            end
            if isfield(cfg, 'pilote_idx')
                nopt = length(get(app.ui.pop_pilote, 'String'));
                if cfg.pilote_idx >= 1 && cfg.pilote_idx <= nopt
                    set(app.ui.pop_pilote, 'Value', cfg.pilote_idx);
                end
            end
            if isfield(cfg, 'fig_position') && length(cfg.fig_position) == 4
                set(fig, 'Position', cfg.fig_position);
            end
            if isfield(cfg, 'zoom_t0'); set(app.ui.edit_t0, 'String', cfg.zoom_t0); end
            if isfield(cfg, 'zoom_t1'); set(app.ui.edit_t1, 'String', cfg.zoom_t1); end
            if isfield(cfg, 'zoom_v0'); set(app.ui.edit_v0, 'String', cfg.zoom_v0); end
            if isfield(cfg, 'zoom_v1'); set(app.ui.edit_v1, 'String', cfg.zoom_v1); end
            guidata(fig, app);
        catch
        end
    end

% #########################################################################
% HELPERS
% #########################################################################

    function doUpdatePlot(app)
        if isempty(app.cur_signal); return; end

        % Limpiar líneas de multi-plot si las hay
        for k = 1:length(app.plot_lines)
            try; if isvalid(app.plot_lines{k}); delete(app.plot_lines{k}); end; catch; end
        end
        app.plot_lines = {};
        legend(app.ui.ax, 'off');
        guidata(fig, app);

        set(app.ui.hline, 'XData', app.cur_time, 'YData', app.cur_signal);

        t0 = str2double(get(app.ui.edit_t0, 'String'));
        t1 = str2double(get(app.ui.edit_t1, 'String'));
        if ~isnan(t0) && ~isnan(t1) && t0 < t1 && t1 <= app.cur_time(end) * 1.001
            xlim(app.ui.ax, [t0 t1]);
        else
            xlim(app.ui.ax, 'auto');
        end
        v0 = str2double(get(app.ui.edit_v0, 'String'));
        v1 = str2double(get(app.ui.edit_v1, 'String'));
        if ~isnan(v0) && ~isnan(v1) && v0 < v1
            ylim(app.ui.ax, [v0 v1]);
        else
            ylim(app.ui.ax, 'auto');
        end

        forceGrid(app.ui.ax);

        [pilote, stk] = getSelectedPilote(app);
        prof          = str2double(get(app.ui.edit_prof, 'String'));
        if isnan(prof); prof = 0; end

        title(app.ui.ax, ...
            sprintf('Pilote: %s  |  Prof: %.2f m  |  Stickup: %.2f m  |  N = %d pts', ...
            pilote, prof, stk, length(app.cur_signal)), 'FontSize', 10);
        drawnow;
    end

    function doMultiPlot(app, datos, sels)
        % Limpiar líneas previas del multiplo
        for k = 1:length(app.plot_lines)
            try; if isvalid(app.plot_lines{k}); delete(app.plot_lines{k}); end; catch; end
        end
        app.plot_lines = {};
        legend(app.ui.ax, 'off');

        hold(app.ui.ax, 'on');

        legend_strs = {};
        curve_idx = 0;
        app.loaded_signals = {};

        % 1) Mantener la señal viva del PSoC si existe
        if ~isempty(app.live_signal) && ~isempty(app.live_time)
            curve_idx = curve_idx + 1;
            set(app.ui.hline, ...
                'XData', app.live_time, ...
                'YData', app.live_signal, ...
                'Color', PLOT_COLORS{1}, ...
                'LineWidth', 1.4, ...
                'Visible', 'on');
            legend_strs{curve_idx} = 'PSoC viva';
            app.loaded_signals{curve_idx} = struct( ...
                'signal', app.live_signal(:), ...
                'time',   app.live_time(:), ...
                'color',  PLOT_COLORS{1}, ...
                'label',  'Adquirida PSoC');
        else
            set(app.ui.hline, 'XData', NaN, 'YData', NaN);
        end

        % 2) Agregar registros del .mat sin borrar la señal viva
        for k = 1:length(sels)
            color_slot = mod(curve_idx, length(PLOT_COLORS)) + 1;
            col = PLOT_COLORS{color_slot};
            rec = datos(sels(k));

            curve_idx = curve_idx + 1;
            h = plot(app.ui.ax, rec.tiempo(:), rec.senal(:), ...
                'Color', col, 'LineWidth', 1.2);

            app.plot_lines{end+1} = h; %#ok<AGROW>
            legend_strs{curve_idx} = sprintf('[%d] %s  %.2f m', ...
                sels(k), rec.pilote, rec.profundidad); %#ok<AGROW>

            app.loaded_signals{curve_idx} = struct( ...
                'signal', rec.senal(:), ...
                'time',   rec.tiempo(:), ...
                'color',  col, ...
                'label',  sprintf('[%d] %s @ %.2fm', sels(k), rec.pilote, rec.profundidad)); %#ok<AGROW>
        end

        hold(app.ui.ax, 'off');

        t0 = str2double(get(app.ui.edit_t0, 'String'));
        t1 = str2double(get(app.ui.edit_t1, 'String'));
        if ~isnan(t0) && ~isnan(t1) && t0 < t1
            xlim(app.ui.ax, [t0 t1]);
        else
            xlim(app.ui.ax, 'auto');
        end

        v0 = str2double(get(app.ui.edit_v0, 'String'));
        v1 = str2double(get(app.ui.edit_v1, 'String'));
        if ~isnan(v0) && ~isnan(v1) && v0 < v1
            ylim(app.ui.ax, [v0 v1]);
        else
            ylim(app.ui.ax, 'auto');
        end

        forceGrid(app.ui.ax);

        total_curves = length(app.loaded_signals);
        if total_curves == 1
            if ~isempty(app.live_signal)
                title(app.ui.ax, 'Señal viva del PSoC', 'FontSize', 10);
            else
                rec = datos(sels(1));
                title(app.ui.ax, ...
                    sprintf('Pilote: %s  |  Prof: %.2f m  |  Stickup: %.2f m  |  N = %d pts', ...
                    rec.pilote, rec.profundidad, rec.stickup, length(rec.senal)), 'FontSize', 10);
            end
        else
            title(app.ui.ax, sprintf('%d señales superpuestas', total_curves), 'FontSize', 10);
        end

        % leyenda: incluir hline si existe señal viva
        hh = gobjects(0);
        if ~isempty(app.live_signal)
            hh(end+1) = app.ui.hline; %#ok<AGROW>
        end
        for k = 1:length(app.plot_lines)
            hh(end+1) = app.plot_lines{k}; %#ok<AGROW>
        end
        if ~isempty(hh)
            legend(app.ui.ax, hh, legend_strs, 'Location', 'best', 'FontSize', 8);
        end

        % cur_signal/cur_time: conservar la viva como referencia si existe
        if ~isempty(app.live_signal)
            app.cur_signal = app.live_signal(:);
            app.cur_time   = app.live_time(:);
        elseif ~isempty(sels)
            app.cur_signal = datos(sels(end)).senal(:);
            app.cur_time   = datos(sels(end)).tiempo(:);
        else
            app.cur_signal = [];
            app.cur_time   = [];
        end

        guidata(fig, app);
        doUpdateStats(app);
        renderTreeItems(app);
        drawnow;
    end

    function doUpdateStats(app)
        NMAX = length(PLOT_COLORS);

        % Ocultar todos los labels
        for s_i = 1:5
            for k_i = 1:NMAX
                set(app.ui.stat_vals{s_i, k_i}, 'Visible', 'off', 'String', '');
            end
        end
        if isempty(app.loaded_signals); return; end

        n = min(length(app.loaded_signals), NMAX);

        % Zona de valores más ancha y mejor distribuida
        x0 = 0.30;       % inicio horizontal de valores
        x1 = 0.985;      % fin horizontal de valores
        gap = 0.008;     % separación entre columnas
        val_w = (x1 - x0 - (n-1)*gap) / n;

        for k = 1:n
            ls  = app.loaded_signals{k};
            sig = ls.signal(:);
            t   = ls.time(:);
            col = ls.color;
            x   = x0 + (k-1)*(val_w + gap);

            try
                vals = [max(sig), min(sig), mean(sig), rms(sig), t(end)];
            catch
                vals = [max(sig), min(sig), mean(sig), sqrt(mean(sig.^2)), t(end)];
            end

            for s_i = 1:5
                set(app.ui.stat_vals{s_i, k}, ...
                    'String', sprintf('%.3f', vals(s_i)), ...
                    'Units', 'normalized', ...
                    'Position', [x, STAT_YPOS(s_i), val_w, 0.11], ...
                    'ForegroundColor', col, ...
                    'Visible', 'on', ...
                    'HorizontalAlignment', 'center', ...
                    'FontSize', 10, ...
                    'FontWeight', 'bold');
            end
        end
    end

    function refreshRecordsList()
        app   = guidata(fig);
        mfolder = strtrim(get(app.ui.edit_matfile, 'String'));
        items = {};
        tgroups = {};
        n     = 0;

        if isfolder(mfolder)
            try
                datos = loadAllDatos(mfolder);
                n = length(datos);
                if n > 0
                    % ── Construir grupos: pilote → profundidad → mediciones ──
                    groups = {};
                    for idx = 1:n
                        d = datos(idx);
                        pg = 0;
                        for p = 1:length(groups)
                            if strcmp(groups{p}.name, d.pilote); pg = p; break; end
                        end
                        if pg == 0
                            groups{end+1} = struct('name', d.pilote, 'profs', {{}}); %#ok<AGROW>
                            pg = length(groups);
                        end
                        rg = 0;
                        profs = groups{pg}.profs;
                        for r = 1:length(profs)
                            if abs(profs{r}.prof - d.profundidad) < 0.001; rg = r; break; end
                        end
                        if rg == 0
                            profs{end+1} = struct('prof', d.profundidad, 'records', {{}}); %#ok<AGROW>
                            rg = length(profs);
                        end
                        profs{rg}.records{end+1} = struct('idx', idx, 'fecha', d.fecha);
                        groups{pg}.profs = profs;
                    end

                    % ── Renderizar árbol ─────────────────────────────────────
                    for p = 1:length(groups)
                        g = groups{p};
                        ng = sum(cellfun(@(x) length(x.records), g.profs));
                        if ng == 1; sfx = 'medicion'; else; sfx = 'mediciones'; end
                        items{end+1} = sprintf('■ %s  (%d %s)', g.name, ng, sfx); %#ok<AGROW>
                        % pilote header → todos los índices bajo este pilote
                        pilote_idxs = [];
                        np = length(g.profs);
                        for r = 1:np
                            pr = g.profs{r};
                            for k = 1:length(pr.records)
                                pilote_idxs(end+1) = pr.records{k}.idx; %#ok<AGROW>
                            end
                        end
                        tgroups{end+1} = pilote_idxs; %#ok<AGROW>

                        for r = 1:np
                            pr = g.profs{r};
                            nr = length(pr.records);
                            is_last = (r == np);
                            if is_last
                                prof_pfx = '  └ ';
                                rec_pfx  = '      ';
                            else
                                prof_pfx = '  ├ ';
                                rec_pfx  = '  │   ';
                            end
                            if nr == 1; sfx2 = 'medicion'; else; sfx2 = 'mediciones'; end
                            items{end+1} = sprintf('%s%.2f m  (%d %s)', prof_pfx, pr.prof, nr, sfx2); %#ok<AGROW>
                            % profundidad header → todos los índices bajo esta profundidad
                            prof_idxs = cellfun(@(x) x.idx, pr.records);
                            tgroups{end+1} = prof_idxs; %#ok<AGROW>
                            for k = 1:nr
                                rec = pr.records{k};
                                items{end+1} = sprintf('%s· [%d] %s', rec_pfx, rec.idx, rec.fecha); %#ok<AGROW>
                                tgroups{end+1} = rec.idx; %#ok<AGROW>
                            end
                        end
                    end
                end
            catch e
                items = {['[Error al leer: ' e.message ']']};
                tgroups = {[]};
            end
        end

        if isempty(items)
            items = {'(carpeta vacía o no encontrada)'};
            tgroups = {[]};
        end

        app.tree_groups     = tgroups;
        app.tree_items_base = items;
        app.loaded_data_idxs = [];
        guidata(fig, app);
        set(app.ui.list_rec, 'String', items, 'Value', []);

        set(app.ui.lbl_nrec, 'String', sprintf('Registros: %d', n));
    end

    function datos = loadAllDatos(folder)
        % Carga y fusiona pilote_datos de todos los .mat en la carpeta
        datos = [];
        if ~isfolder(folder); return; end
        files = dir(fullfile(folder, '*.mat'));
        for kk = 1:length(files)
            try
                tmp = load(fullfile(folder, files(kk).name), 'pilote_datos');
                if isfield(tmp, 'pilote_datos') && ~isempty(tmp.pilote_datos)
                    if isempty(datos); datos = tmp.pilote_datos;
                    else;              datos = [datos, tmp.pilote_datos]; end %#ok<AGROW>
                end
            catch
            end
        end
    end

    function pilote_datos = loadPiloteDatos(folder, nombre)
        % Carga pilote_datos de un .mat específico de pilote
        pilote_datos = [];
        fname = matFileForPilote(folder, nombre);
        if exist(fname, 'file') ~= 2; return; end
        try
            tmp = load(fname, 'pilote_datos');
            if isfield(tmp, 'pilote_datos')
                pilote_datos = tmp.pilote_datos;
            end
        catch
        end
    end

    function pilote_info = getPiloteInfoByName(folder, nombre)
        % Carga pilote_info de un .mat específico de pilote
        pilote_info = [];
        fname = matFileForPilote(folder, nombre);
        if exist(fname, 'file') ~= 2; return; end
        try
            tmp = load(fname, 'pilote_info');
            if isfield(tmp, 'pilote_info')
                pilote_info = tmp.pilote_info;
            end
        catch
        end
    end

    function fname = matFileForPilote(folder, nombre)
        % Devuelve la ruta del .mat para un pilote dado (nombre sanitizado)
        safe = regexprep(nombre, '[^a-zA-Z0-9_\-]', '_');
        fname = fullfile(folder, [safe '.mat']);
    end

    function savePiloteFile(folder, pilote_info, pilote_datos) %#ok<INUSL>
        % Guarda un archivo .mat con la info y datos de un pilote
        if ~isfolder(folder); mkdir(folder); end
        fname = matFileForPilote(folder, pilote_info.nombre);
        save(fname, 'pilote_info', 'pilote_datos');
    end

% ── Gestión de pilotes ───────────────────────────────────────────────────

    function onNewPilote(~, ~)
        % Abre la ventana modal de gestión de pilotes
        app   = guidata(fig);
        mfolder = strtrim(get(app.ui.edit_matfile, 'String'));
        if isempty(mfolder); mfolder = def_matfolder; end

        % ── Figura modal ────────────────────────────────────────────────
        dlg = figure( ...
            'Name',        'Gestión de Pilotes', ...
            'NumberTitle', 'off', ...
            'Position',    [200 200 420 400], ...
            'Resize',      'off', ...
            'Color',       C_BG, ...
            'WindowStyle', 'modal', ...
            'CloseRequestFcn', @dlgClose);

        % ── Lista de pilotes existentes ──────────────────────────────────
        uicontrol(dlg, 'Style', 'text', ...
            'String', 'Pilotes registrados:', ...
            'Units', 'pixels', 'Position', [10 360 200 22], ...
            'HorizontalAlignment', 'left', 'BackgroundColor', C_BG, ...
            'FontWeight', 'bold');

        dlg_list = uicontrol(dlg, 'Style', 'listbox', ...
            'Units', 'pixels', 'Position', [10 230 400 128], ...
            'FontSize', 9, 'BackgroundColor', [1 1 1]);

        % ── Separador y título sección alta ─────────────────────────────
        uicontrol(dlg, 'Style', 'text', ...
            'String', '─── Nuevo pilote ───────────────────────────', ...
            'Units', 'pixels', 'Position', [10 200 400 20], ...
            'HorizontalAlignment', 'left', 'BackgroundColor', C_BG, ...
            'ForegroundColor', [0.4 0.4 0.4]);

        % Nombre
        uicontrol(dlg, 'Style', 'text', 'String', 'Nombre / ID:', ...
            'Units', 'pixels', 'Position', [10 168 110 22], ...
            'HorizontalAlignment', 'left', 'BackgroundColor', C_BG);
        dlg_nombre = uicontrol(dlg, 'Style', 'edit', 'String', '', ...
            'Units', 'pixels', 'Position', [125 168 275 24], ...
            'BackgroundColor', [1 1 1]);

        % Stickup
        uicontrol(dlg, 'Style', 'text', 'String', 'Stickup (m):', ...
            'Units', 'pixels', 'Position', [10 132 110 22], ...
            'HorizontalAlignment', 'left', 'BackgroundColor', C_BG);
        dlg_stickup = uicontrol(dlg, 'Style', 'edit', 'String', '0.500', ...
            'Units', 'pixels', 'Position', [125 132 120 24], ...
            'BackgroundColor', [1 1 1]);

        % ── Botones ──────────────────────────────────────────────────────
        uicontrol(dlg, 'Style', 'pushbutton', 'String', 'AGREGAR', ...
            'Units', 'pixels', 'Position', [10 88 120 32], ...
            'FontWeight', 'bold', 'FontSize', 9, ...
            'BackgroundColor', dlgBtnBg(C_GRN), ...
            'ForegroundColor', [0 0 0], 'Callback', @dlgAgregar);

        uicontrol(dlg, 'Style', 'pushbutton', 'String', 'ELIMINAR SELECCIONADO', ...
            'Units', 'pixels', 'Position', [140 88 270 32], ...
            'FontWeight', 'bold', 'FontSize', 9, ...
            'BackgroundColor', dlgBtnBg(C_RED), ...
            'ForegroundColor', [0 0 0], 'Callback', @dlgEliminar);

        uicontrol(dlg, 'Style', 'pushbutton', 'String', 'CERRAR', ...
            'Units', 'pixels', 'Position', [10 44 400 32], ...
            'FontWeight', 'bold', 'FontSize', 9, ...
            'BackgroundColor', dlgBtnBg([0.4 0.4 0.4]), ...
            'ForegroundColor', [0 0 0], 'Callback', @dlgClose);

        uicontrol(dlg, 'Style', 'text', 'String', '', ...
            'Tag', 'dlg_status', ...
            'Units', 'pixels', 'Position', [10 12 400 26], ...
            'HorizontalAlignment', 'left', 'BackgroundColor', C_BG, ...
            'ForegroundColor', C_BLU, 'FontWeight', 'bold');

        dlgRefreshList();   % poblar lista inicial
        uiwait(dlg);        % bloquear hasta que se cierre

        % Al volver, refrescar dropdown principal
        refreshPilotesList();
        onPiloteChanged([], []);

        % ── Callbacks internos del diálogo ───────────────────────────────
        function dlgRefreshList()
            pilotes = loadAllPilotes(mfolder);
            if isempty(pilotes)
                set(dlg_list, 'String', {'(no hay pilotes registrados)'}, 'Value', 1);
            else
                items = cell(1, length(pilotes));
                for jj = 1:length(pilotes)
                    items{jj} = sprintf('%-14s  stk: %.3f m    [%s]', ...
                        pilotes(jj).nombre, pilotes(jj).stickup, pilotes(jj).fecha_reg);
                end
                cur = min(get(dlg_list, 'Value'), length(items));
                set(dlg_list, 'String', items, 'Value', max(1, cur));
            end
        end

        function dlgAgregar(~, ~)
            nombre = strtrim(get(dlg_nombre, 'String'));
            stk    = str2double(get(dlg_stickup, 'String'));
            lbl    = findobj(dlg, 'Tag', 'dlg_status');

            if isempty(nombre)
                set(lbl, 'String', 'Error: el nombre no puede estar vacío.', ...
                    'ForegroundColor', C_RED); return;
            end
            if isnan(stk) || stk < 0
                set(lbl, 'String', 'Error: stickup debe ser un número ≥ 0.', ...
                    'ForegroundColor', C_RED); return;
            end

            pilotes = loadAllPilotes(mfolder);
            for jj = 1:length(pilotes)
                if strcmpi(pilotes(jj).nombre, nombre)
                    set(lbl, 'String', ...
                        sprintf('Error: "%s" ya existe.', nombre), ...
                        'ForegroundColor', C_RED); return;
                end
            end

            nuevo_p.nombre    = nombre;
            nuevo_p.stickup   = stk;
            nuevo_p.fecha_reg = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

            pilote_datos = []; %#ok<NASGU>
            try
                savePiloteFile(mfolder, nuevo_p, pilote_datos);
                set(dlg_nombre,  'String', '');
                set(dlg_stickup, 'String', '0.500');
                set(lbl, 'String', sprintf('Pilote "%s" agregado.', nombre), ...
                    'ForegroundColor', C_GRN);
                dlgRefreshList();
            catch err
                set(lbl, 'String', ['Error al guardar: ' err.message], ...
                    'ForegroundColor', C_RED);
            end
        end

        function dlgEliminar(~, ~)
            pilotes = loadAllPilotes(mfolder);
            lbl     = findobj(dlg, 'Tag', 'dlg_status');
            if isempty(pilotes)
                set(lbl, 'String', 'No hay pilotes para eliminar.', ...
                    'ForegroundColor', C_RED); return;
            end

            sel = get(dlg_list, 'Value');
            if sel < 1 || sel > length(pilotes); return; end

            nombre_del = pilotes(sel).nombre;
            confirm = questdlg( ...
                sprintf('¿Eliminar el pilote "%s"?\nEsto eliminará también todas sus mediciones.', nombre_del), ...
                'Confirmar', 'Eliminar', 'Cancelar', 'Cancelar');
            if ~strcmp(confirm, 'Eliminar'); return; end

            try
                fname_del = matFileForPilote(mfolder, nombre_del);
                if exist(fname_del, 'file') == 2
                    delete(fname_del);
                end
                set(lbl, 'String', sprintf('Pilote "%s" eliminado.', nombre_del), ...
                    'ForegroundColor', C_ORG);
                dlgRefreshList();
            catch err
                set(lbl, 'String', ['Error al eliminar: ' err.message], ...
                    'ForegroundColor', C_RED);
            end
        end

        function dlgClose(~, ~)
            uiresume(dlg);
            delete(dlg);
        end
    end

    function onPiloteChanged(~, ~)
        % Actualiza el label de stickup cuando cambia la selección del dropdown
        app     = guidata(fig);
        [~, stk] = getSelectedPilote(app);
        if isnan(stk)
            set(app.ui.lbl_stickup_val, 'String', '—');
        else
            set(app.ui.lbl_stickup_val, 'String', sprintf('%.3f', stk));
        end
    end

    function refreshPilotesList()
        app   = guidata(fig);
        mfolder = strtrim(get(app.ui.edit_matfile, 'String'));

        pilotes = loadAllPilotes(mfolder);
        app.pilotes = pilotes;
        guidata(fig, app);

        if isempty(pilotes)
            set(app.ui.pop_pilote, 'String', {'(sin pilotes)'}, 'Value', 1);
            set(app.ui.lbl_stickup_val, 'String', '—');
        else
            nombres = {pilotes.nombre};
            cur_val = get(app.ui.pop_pilote, 'Value');
            set(app.ui.pop_pilote, 'String', nombres, ...
                'Value', min(cur_val, length(nombres)));
            onPiloteChanged([], []);
        end
    end

    function pilotes = loadAllPilotes(folder)
        % Carga pilote_info de todos los .mat en la carpeta
        pilotes = [];
        if ~isfolder(folder); return; end
        files = dir(fullfile(folder, '*.mat'));
        for kk = 1:length(files)
            try
                tmp = load(fullfile(folder, files(kk).name), 'pilote_info');
                if isfield(tmp, 'pilote_info') && ~isempty(tmp.pilote_info)
                    if isempty(pilotes); pilotes = tmp.pilote_info;
                    else;                pilotes(end+1) = tmp.pilote_info; end %#ok<AGROW>
                end
            catch
            end
        end
    end

    function [nombre, stk] = getSelectedPilote(app)
        % Devuelve el nombre y stickup del pilote seleccionado en el popup
        nombre = '';
        stk    = NaN;
        if isempty(app.pilotes); return; end
        idx = get(app.ui.pop_pilote, 'Value');
        if idx < 1 || idx > length(app.pilotes); return; end
        nombre = app.pilotes(idx).nombre;
        stk    = app.pilotes(idx).stickup;
    end

% ── Helper para color de fondo de botones en diálogos (idéntica lógica a mkbtn) ──
    function bg_out = dlgBtnBg(bg)
        lum = 0.2126*bg(1) + 0.7152*bg(2) + 0.0722*bg(3);
        if ispc() && lum < 0.5
            bg_out = min(bg * 0.65 + [0.35 0.35 0.35], [1 1 1]);
        else
            bg_out = bg;
        end
    end

% ── Factories de controles (evitan repetición) ───────────────────────────
    function h = mkpanel(parent, ttl, pos)
        h = uipanel(parent, 'Title', ttl, ...
            'Units', 'normalized', 'Position', pos, ...
            'FontWeight', 'bold', 'FontSize', 9.5, ...
            'BackgroundColor', C_BG);
    end

    function h = mktext(parent, str, pos)
        h = uicontrol(parent, 'Style', 'text', 'String', str, ...
            'Units', 'normalized', 'Position', pos, ...
            'HorizontalAlignment', 'left', 'BackgroundColor', C_BG);
    end

    function h = mkvaltext(parent, str, pos)
        h = uicontrol(parent, 'Style', 'text', 'String', str, ...
            'Units', 'normalized', 'Position', pos, ...
            'HorizontalAlignment', 'right', 'FontWeight', 'bold', ...
            'BackgroundColor', C_BG);
    end

    function h = mkedit(parent, str, pos)
        h = uicontrol(parent, 'Style', 'edit', 'String', str, ...
            'Units', 'normalized', 'Position', pos, ...
            'BackgroundColor', C_WHT);
    end

    function h = mkbtn(parent, str, pos, bg, cb, fs)
        if nargin < 6; fs = 9; end
        lum = 0.2126*bg(1) + 0.7152*bg(2) + 0.0722*bg(3);
        if ispc() && lum < 0.5
            bg_use = min(bg * 0.65 + [0.35 0.35 0.35], [1 1 1]);
            fg_use = [0 0 0];
        elseif lum > 0.5
            bg_use = bg;
            fg_use = [0 0 0];
        else
            bg_use = bg;
            fg_use = [1 1 1];
        end
        h = uicontrol(parent, 'Style', 'pushbutton', 'String', str, ...
            'Units', 'normalized', 'Position', pos, ...
            'FontWeight', 'bold', 'FontSize', fs, ...
            'BackgroundColor', bg_use, ...
            'ForegroundColor', fg_use, 'Callback', cb);
    end

    function renderTreeItems(app)
        % Redibuja el listbox marcando con ►k los registros cargados
        % donde k = slot de color (1=azul, 2=rojo, etc.)
        items = app.tree_items_base;
        if isempty(items)
            set(app.ui.list_rec, 'String', items);
            return;
        end
        tg     = app.tree_groups;
        loaded = app.loaded_data_idxs;  % en orden de slot
        if ~isempty(loaded)
            for i = 1:min(length(items), length(tg))
                if length(tg{i}) == 1
                    slot = find(loaded == tg{i}(1), 1);
                    if ~isempty(slot)
                        marker = sprintf('%s%d', char(9658), slot); % ►k
                        items{i} = strrep(items{i}, char(183), marker); % · → ►k
                    end
                end
            end
        end
        set(app.ui.list_rec, 'String', items);
    end

    function labels = getPortLabels(ports)
        % Devuelve etiquetas "COMx – Nombre del dispositivo" en Windows.
        % En otros SO devuelve los nombres tal cual.
        if isstring(ports); ports = cellstr(ports); end
        if ischar(ports);   ports = {ports}; end
        labels = ports;
        if ~ispc || isempty(ports); return; end
        try
            [~, raw] = system('wmic path Win32_PnPEntity where "Name like ''%(COM%''" get Name /format:list');
            lines = strsplit(raw, newline);
            for k = 1:length(ports)
                tag = ['(' ports{k} ')'];
                for j = 1:length(lines)
                    ln = strtrim(lines{j});
                    if length(ln) > 5 && strcmp(ln(1:5), 'Name=') && contains(ln, tag)
                        desc = strtrim(ln(6:end));
                        desc = strtrim(regexprep(desc, ['\s*\(', ports{k}, '\)\s*$'], ''));
                        labels{k} = [ports{k} ' – ' desc];
                        break;
                    end
                end
            end
        catch
            % Si wmic falla, usar nombres de puerto simples
        end
    end

    function forceGrid(ax)
        grid(ax, 'on');
        ax.XMinorTick = 'on';
        ax.YMinorTick = 'on';
        ax.XMinorGrid = 'on';
        ax.YMinorGrid = 'on';
        ax.GridAlpha = 0.25;
        ax.MinorGridAlpha = 0.12;
        ax.Layer = 'top';
    end
end % interfaz_transductor
