const searchInput = document.querySelector('#reservation-search');

if (searchInput) {
  searchInput.addEventListener('input', (event) => {
    const query = event.target.value.toLowerCase();
    document.querySelectorAll('#reservation-table tbody tr').forEach((row) => {
      row.hidden = !row.textContent.toLowerCase().includes(query);
    });
  });
}

document.querySelectorAll('[data-open-dialog]').forEach((button) => {
  button.addEventListener('click', () => {
    document.getElementById(button.dataset.openDialog)?.showModal();
  });
});

document.querySelectorAll('[data-close-dialog]').forEach((button) => {
  button.addEventListener('click', () => button.closest('dialog')?.close());
});

document.querySelectorAll('.extend-dialog[data-current-departure]').forEach((dialog) => {
  const departureInput = dialog.querySelector('input[name="check_out"]');
  const quote = dialog.querySelector('.extension-quote');
  const nightlyRate = Number(dialog.dataset.nightlyRate);
  const [currentYear, currentMonth, currentDay] = dialog.dataset.currentDeparture.split('-').map(Number);
  departureInput.min = new Date(Date.UTC(currentYear, currentMonth - 1, currentDay) + 86400000)
    .toISOString()
    .slice(0, 10);

  departureInput.addEventListener('input', () => {
    if (!departureInput.value) {
      quote.textContent = `Added nights are charged at ₦${nightlyRate.toLocaleString()} per night.`;
      return;
    }
    const [year, month, day] = departureInput.value.split('-').map(Number);
    const addedNights = (Date.UTC(year, month - 1, day) - Date.UTC(currentYear, currentMonth - 1, currentDay)) / 86400000;
    const additionalCharge = addedNights * nightlyRate;
    quote.textContent = `${addedNights} added night(s) · Additional charge: ₦${additionalCharge.toLocaleString()}.`;
  });
});

document.querySelectorAll('.public-room-booking-form').forEach((form) => {
  const dialog = form.querySelector('.public-guest-dialog');
  const roomSummary = dialog?.querySelector('.public-selected-room');

  if (!dialog || !roomSummary) return;

  form.querySelectorAll('input[name="room_number"]').forEach((roomInput) => {
    roomInput.addEventListener('change', () => {
      if (!roomInput.checked) return;
      roomSummary.textContent = `Selected: Room ${roomInput.value}`;
      dialog.showModal();
      dialog.querySelector('input[name="guest_name"]')?.focus();
    });
  });

  dialog.addEventListener('close', () => {
    const selectedRoom = form.querySelector('input[name="room_number"]:checked');
    if (selectedRoom) selectedRoom.checked = false;
  });
});
