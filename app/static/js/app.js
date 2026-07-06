/* ── state ── */
let objUrl = null
let points = []

/* ── refs ── */
const form      = document.getElementById('form')
const fileInput = document.getElementById('fileInput')
const drop      = document.getElementById('drop')
const previewWrap = document.getElementById('previewWrap')
const imgPreview  = document.getElementById('imgPreview')
const vidPreview  = document.getElementById('vidPreview')
const canvas    = document.getElementById('canvas')
const ctx       = canvas.getContext('2d')
const lineMode  = document.getElementById('lineMode')
const lineHint  = document.getElementById('lineHint')
const resetLine = document.getElementById('resetLine')
const clearBtn  = document.getElementById('clearBtn')
const submitBtn = document.getElementById('submitBtn')
const progress  = document.getElementById('progress')
const errorBox  = document.getElementById('errorBox')
const resultCard = document.getElementById('resultCard')

/* ── health ── */
async function checkHealth() {
  const badge = document.getElementById('healthBadge')
  try {
    const r = await fetch('/api/health')
    if (r.ok) { badge.textContent = '● сервер работает'; badge.classList.add('ok') }
    else throw new Error()
  } catch { badge.textContent = '● сервер недоступен' }
}

/* ── file handling ── */
function setFile(file) {
  if (!file) return
  const dt = new DataTransfer(); dt.items.add(file); fileInput.files = dt.files
  if (objUrl) URL.revokeObjectURL(objUrl)
  objUrl = URL.createObjectURL(file)
  previewWrap.classList.remove('hidden')
  points = []; clearCoords(); drawLine()
  const isVideo = file.type.startsWith('video/')
  imgPreview.classList.toggle('hidden', isVideo)
  vidPreview.classList.toggle('hidden', !isVideo)
  if (isVideo) { vidPreview.src = objUrl; vidPreview.onloadedmetadata = resizeCanvas }
  else { imgPreview.src = objUrl; imgPreview.onload = resizeCanvas }
  updateLineMode()
}

function clearFile() {
  if (objUrl) { URL.revokeObjectURL(objUrl); objUrl = null }
  fileInput.value = ''
  imgPreview.src = ''; imgPreview.classList.add('hidden')
  vidPreview.src = ''; vidPreview.classList.add('hidden')
  previewWrap.classList.add('hidden')
  points = []; clearCoords()
  errorBox.classList.add('hidden')
}

function resizeCanvas() {
  const el = imgPreview.classList.contains('hidden') ? vidPreview : imgPreview
  const r = el.getBoundingClientRect()
  canvas.width  = Math.round(r.width)  || 1
  canvas.height = Math.round(r.height) || 1
  drawLine()
}

function drawLine() {
  ctx.clearRect(0, 0, canvas.width, canvas.height)
  if (!points.length) return
  ctx.fillStyle = '#ffdc2e'
  for (const p of points) {
    ctx.beginPath()
    ctx.arc(p.x * canvas.width, p.y * canvas.height, 6, 0, Math.PI * 2)
    ctx.fill()
  }
  if (points.length === 2) {
    ctx.strokeStyle = '#ffdc2e'; ctx.lineWidth = 3
    ctx.beginPath()
    ctx.moveTo(points[0].x * canvas.width, points[0].y * canvas.height)
    ctx.lineTo(points[1].x * canvas.width, points[1].y * canvas.height)
    ctx.stroke()
    setCoords()
  }
}

function setCoords() {
  const ids = ['x1','y1','x2','y2']
  const vals = [points[0].x, points[0].y, points[1].x, points[1].y]
  ids.forEach((id, i) => document.getElementById(id).value = vals[i])
}

function clearCoords() {
  ['x1','y1','x2','y2'].forEach(id => document.getElementById(id).value = '')
}

function updateLineMode() {
  const manual = lineMode.value === 'manual'
  canvas.style.pointerEvents = manual ? 'auto' : 'none'
  resetLine.classList.toggle('hidden', !manual)
  lineHint.classList.toggle('hidden', !manual)
}

/* ── canvas click ── */
canvas.addEventListener('click', e => {
  if (lineMode.value !== 'manual') return
  const r = canvas.getBoundingClientRect()
  const p = { x: (e.clientX - r.left) / r.width, y: (e.clientY - r.top) / r.height }
  if (points.length >= 2) { points = []; clearCoords() }
  points.push(p); drawLine()
})

resetLine.addEventListener('click', () => { points = []; clearCoords(); drawLine() })
clearBtn.addEventListener('click', clearFile)
lineMode.addEventListener('change', updateLineMode)
fileInput.addEventListener('change', () => setFile(fileInput.files[0]))
window.addEventListener('resize', resizeCanvas)

drop.addEventListener('dragover', e => { e.preventDefault(); drop.classList.add('over') })
drop.addEventListener('dragleave', () => drop.classList.remove('over'))
drop.addEventListener('drop', e => { e.preventDefault(); drop.classList.remove('over'); setFile(e.dataTransfer.files[0]) })

/* ── submit ── */
form.addEventListener('submit', async e => {
  e.preventDefault()
  errorBox.classList.add('hidden')
  if (lineMode.value === 'manual' && points.length !== 2) {
    showError('Укажите две точки стоп-линии на предпросмотре.'); return
  }
  progress.classList.remove('hidden')
  submitBtn.disabled = true
  try {
    const res = await fetch('/api/analyze', { method: 'POST', body: new FormData(form) })
    const data = await res.json()
    if (!res.ok) throw new Error(data.detail || 'Ошибка анализа')
    renderResult(data)
    loadHistory()
  } catch (err) {
    showError(err.message)
  } finally {
    progress.classList.add('hidden')
    submitBtn.disabled = false
  }
})

function showError(msg) { errorBox.textContent = msg; errorBox.classList.remove('hidden') }

/* ── result ── */
function renderResult(d) {
  resultCard.classList.remove('hidden')
  const signalNames = { red: 'красный', yellow: 'жёлтый', green: 'зелёный', unknown: 'не определён' }
  const statData = [
    ['Автомобили', d.detected_vehicles],
    ['Нарушения', d.violations],
    ['Сигнал', signalNames[d.traffic_light_state] || d.traffic_light_state],
    ['Время, с', d.processing_seconds?.toFixed(1) ?? '—'],
  ]
  document.getElementById('stats').innerHTML = statData.map(([l, v]) =>
    `<div class="stat"><div class="stat-label">${l}</div><div class="stat-val">${v}</div></div>`
  ).join('')
  document.getElementById('pdfLink').href = d.pdf_url
  document.getElementById('xlsLink').href = d.excel_url
  const media = d.media_type === 'image'
    ? `<img src="${d.result_url}?t=${Date.now()}" alt="Результат">`
    : `<video src="${d.result_url}?t=${Date.now()}" controls style="max-width:100%;border-radius:10px"></video>`
  document.getElementById('resultMedia').innerHTML = media
  const events = d.details?.events || []
  document.getElementById('eventList').innerHTML = events.length
    ? events.map(ev =>
        `<div class="event"><strong>Событие ${ev.event_number}</strong> &mdash; ${ev.vehicle_class} · уверенность ${ev.confidence?.toFixed(2)}${ev.time_seconds !== undefined ? ` · ${ev.time_seconds} с` : ''} · ${ev.traffic_light_state || ''}</div>`
      ).join('')
    : ''
  resultCard.scrollIntoView({ behavior: 'smooth' })
}

/* ── history ── */
async function loadHistory() {
  const body = document.getElementById('histBody')
  body.innerHTML = '<tr><td colspan="6" style="color:#888;padding:12px">Загрузка…</td></tr>'
  try {
    const res = await fetch('/api/history')
    const items = await res.json()
    if (!items.length) { body.innerHTML = '<tr><td colspan="6" style="color:#888;padding:12px">История пуста</td></tr>'; return }
    body.innerHTML = items.map(it => {
      const date = new Date(it.created_at).toLocaleString('ru-RU')
      const count = it.violations
      return `<tr>
        <td>${date}</td>
        <td>${esc(it.source_name)}</td>
        <td>${it.media_type === 'image' ? 'Фото' : 'Видео'}</td>
        <td>${it.detected_vehicles}</td>
        <td>${count}</td>
        <td><a href="${it.pdf_url}">PDF</a> &middot; <a href="${it.excel_url}">Excel</a></td>
      </tr>`
    }).join('')
  } catch { body.innerHTML = '<tr><td colspan="6" style="color:#c00;padding:12px">Ошибка загрузки</td></tr>' }
}

function esc(s) {
  const d = document.createElement('div'); d.textContent = s; return d.innerHTML
}

document.getElementById('refreshBtn').addEventListener('click', loadHistory)
checkHealth()
loadHistory()
