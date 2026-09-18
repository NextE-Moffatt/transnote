// TransNote 面板 - JXA / Cocoa
// 用法: osascript -l JavaScript ui.js <payload.json>
// payload: { mode, title, subtitle, body }
// 返回:   note | copy | close | ok | error

ObjC.import('Cocoa');

function readJSON(path) {
  const str = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
  if (!str || str.isNil()) throw new Error('cannot read payload: ' + path);
  return JSON.parse(str.js);
}

function run(argv) {
  if (!argv || argv.length < 1) return 'error';

  var payload;
  try {
    payload = readJSON(argv[0]);
  } catch (err) {
    return 'error';
  }

  const mode = payload.mode || 'panel';
  const app = $.NSApplication.sharedApplication;
  try { app.setActivationPolicy($.NSApplicationActivationPolicyAccessory); } catch (e) { }

  const alert = $.NSAlert.alloc.init;
  alert.setMessageText($(String(payload.title || '英译中')));
  alert.setInformativeText($(String(payload.subtitle || '')));
  alert.setAlertStyle($.NSAlertStyleInformational);

  if (mode === 'panel') {
    const W = 560;
    const H = 300;

    const scroll = $.NSScrollView.alloc.initWithFrame($.NSMakeRect(0, 0, W, H));
    scroll.setHasVerticalScroller(true);
    scroll.setAutohidesScrollers(true);
    scroll.setBorderType($.NSBezelBorder);
    scroll.setDrawsBackground(true);

    const tv = $.NSTextView.alloc.initWithFrame($.NSMakeRect(0, 0, W, H));
    tv.setEditable(false);
    tv.setSelectable(true);
    tv.setRichText(false);
    tv.setFont($.NSFont.systemFontOfSize(13));
    tv.setTextContainerInset($.NSMakeSize(8, 8));
    tv.setVerticallyResizable(true);
    tv.setHorizontallyResizable(false);
    tv.setMinSize($.NSMakeSize(0, 0));
    tv.setMaxSize($.NSMakeSize(W, 1000000));
    tv.textContainer.setContainerSize($.NSMakeSize(W, 1000000));
    tv.textContainer.setWidthTracksTextView(true);
    tv.setString($(String(payload.body || '')));
    scroll.setDocumentView(tv);

    alert.setAccessoryView(scroll);
    alert.addButtonWithTitle($('加入笔记'));
    alert.addButtonWithTitle($('复制译文'));
    alert.addButtonWithTitle($('关闭'));
  } else {
    alert.addButtonWithTitle($('好'));
  }

  try { app.activateIgnoringOtherApps(true); } catch (e) { }

  const resp = Number(alert.runModal);

  if (mode !== 'panel') return 'ok';
  if (resp === 1000) return 'note';
  if (resp === 1001) return 'copy';
  return 'close';
}
